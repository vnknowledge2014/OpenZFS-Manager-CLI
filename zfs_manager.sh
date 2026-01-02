#!/usr/bin/env bash

# ==============================================================================
# SCRIPT: OPENZFS MANAGER (MULTI-PLATFORM)
# Hỗ trợ: macOS, Ubuntu/Debian, NixOS
# Tương thích gọi từ: Bash, Zsh, Fish, Nushell
# ==============================================================================

# --- ĐẢM BẢO CHẠY BẰNG BASH ---
if [ -z "$BASH_VERSION" ]; then
    echo "⚠️  Script này cần chạy bằng Bash. Đang chuyển đổi..."
    exec bash "$0" "$@"
fi

# --- CẤU HÌNH MÀU SẮC ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- BIẾN HỆ THỐNG & PATH SETUP ---
OS_NAME="$(uname -s)"
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~$REAL_USER")

# Tự động thêm các đường dẫn phổ biến của ZFS vào PATH
export PATH="/usr/local/zfs/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# Kiểm tra quyền Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Lỗi: Vui lòng chạy script với quyền sudo!${NC}"
  # Hướng dẫn cụ thể cho từng shell nếu cần
  echo -e "${YELLOW}👉 Bash/Zsh/Fish: sudo $0${NC}"
  echo -e "${YELLOW}👉 Nushell: sudo bash $0${NC}" 
  exit 1
fi

# ==============================================================================
# HÀM HỖ TRỢ: TỰ ĐỘNG SET MOUNTPOINT (Fix lỗi hiển thị GUI)
# ==============================================================================
fix_gui_mountpoint() {
    local POOL_NAME=$1
    
    echo -e "${YELLOW}⚙️  Đang cấu hình hiển thị GUI cho '$POOL_NAME'...${NC}"

    if [[ "$OS_NAME" == "Darwin" ]]; then
        # macOS: Mount vào /Volumes để hiện lên Finder
        zfs set mountpoint="/Volumes/$POOL_NAME" "$POOL_NAME"
    else
        # Linux: Mount vào /media/USER để hiện lên Files (Sidebar)
        if [ ! -d "/media/$REAL_USER" ]; then
            mkdir -p "/media/$REAL_USER"
            chown "$REAL_USER:$REAL_USER" "/media/$REAL_USER"
        fi
        
        TARGET_MOUNT="/media/$REAL_USER/$POOL_NAME"
        zfs set mountpoint="$TARGET_MOUNT" "$POOL_NAME"
    fi
    
    # Cấp quyền cho user thường có thể ghi chép
    local MPOINT=$(zfs get -H -o value mountpoint "$POOL_NAME")
    if [ -d "$MPOINT" ]; then
        chmod 777 "$MPOINT"
        echo -e "${GREEN}✅ Đã mount tại: $MPOINT${NC}"
    fi
}

# ==============================================================================
# 1. KIỂM TRA & CÀI ĐẶT
# ==============================================================================
check_install_zfs() {
    clear
    echo -e "${BLUE}🔍 Đang kiểm tra môi trường OpenZFS...${NC}"
    
    # Kiểm tra lệnh zpool
    if command -v zpool &> /dev/null; then 
        local ZFS_VER=$(zfs --version | head -n 1)
        echo -e "${GREEN}✅ Đã cài đặt: $ZFS_VER${NC}"
        return
    fi

    echo -e "${YELLOW}⚠️  OpenZFS chưa được cài đặt hoặc không tìm thấy trong PATH.${NC}"

    case "${OS_NAME}" in
        Linux*) 
            if [ -f /etc/nixos/configuration.nix ]; then
                echo -e "${RED}❌ Trên NixOS, bạn cần khai báo trong configuration.nix:${NC}"
                echo -e "${CYAN}  boot.supportedFilesystems = [ \"zfs\" ];${NC}"
                echo -e "${CYAN}  networking.hostId = \"$(head -c4 /dev/urandom | od -A none -t x4)\";${NC}"
                echo -e "${YELLOW}👉 Sau đó chạy: sudo nixos-rebuild switch${NC}"
                exit 1
            elif [ -f /etc/debian_version ]; then 
                echo -e "${CYAN}Đang cài đặt trên Debian/Ubuntu...${NC}"
                apt update -qq && apt install -y zfsutils-linux
            elif [ -f /etc/arch-release ]; then 
                pacman -Sy --noconfirm zfs-linux
            else 
                echo -e "${RED}❌ Distro này chưa được hỗ trợ cài tự động.${NC}"
                echo -e "👉 Hãy cài 'zfsutils-linux' hoặc gói tương đương thủ công."; exit 1; 
            fi
            ;; 
        Darwin*) 
            echo -e "${CYAN}Đang cài đặt trên macOS (sử dụng User: $REAL_USER)...${NC}"
            if sudo -u "$REAL_USER" command -v brew &> /dev/null; then 
                # Chạy brew dưới quyền user thường để tránh lỗi permission
                echo -e "${YELLOW}☕ Đang gọi Homebrew...${NC}"
                sudo -u "$REAL_USER" brew install --cask openzfs
                
                # Cần load kext (Kernel Extension) trên macOS
                echo -e "${YELLOW}⚠️  Lưu ý: Bạn có thể cần Approve Kext trong System Settings > Privacy & Security.${NC}"
                echo -e "${YELLOW}   Sau khi Approve, hãy khởi động lại máy nếu cần.${NC}"
            else 
                echo -e "${RED}❌ Không tìm thấy Homebrew! Hãy cài Homebrew trước.${NC}"; exit 1; 
            fi
            ;; 
    esac
    
    # Refresh hash để tìm lệnh mới cài
    hash -r
    
    # Kiểm tra lại sau khi cài
    if ! command -v zpool &> /dev/null; then
        echo -e "${RED}❌ Cài đặt thất bại hoặc cần khởi động lại.${NC}"
        echo -e "${YELLOW}Gợi ý: Kiểm tra lại PATH hoặc thử khởi động lại máy.${NC}"
        exit 1
    fi
}

# ==============================================================================
# 2. IMPORT & MOUNT
# ==============================================================================
scan_and_import() {
    echo -e "${BLUE}--- QUÉT & IMPORT Ổ CỨNG ---${NC}"
    
    # Thử import
    POOLS_AVAIL=$(zpool import 2>/dev/null)
    
    # Nếu không có output import, kiểm tra xem đã import chưa
    if [[ -z "$POOLS_AVAIL" ]]; then
        if zpool list | grep -q "NAME"; then
             echo -e "${GREEN}✅ Các pool đang hoạt động:${NC}"
             zpool list
             return
        fi
        echo -e "${RED}❌ Không tìm thấy pool nào (Exported).${NC}"
        echo -e "${YELLOW}👉 Cắm ổ cứng vào và nhấn Enter để thử lại...${NC}"
        read -r
        scan_and_import
    else
        echo -e "${YELLOW}Tìm thấy pool. Đang Import tất cả...${NC}"
        # -f để force import nếu pool chưa được export sạch sẽ ở máy khác
        zpool import -a -f
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Import thành công! Đang cập nhật điểm gắn kết...${NC}"
            zpool list -H -o name | while read -r pool; do
                fix_gui_mountpoint "$pool"
            done
            zpool list
        else
            echo -e "${RED}❌ Import thất bại. Có thể pool bị hỏng hoặc đang được sử dụng.${NC}"
        fi
    fi
}

# ==============================================================================
# 3. EXPORT (EJECT)
# ==============================================================================
eject_pool() {
    echo -e "${BLUE}--- EJECT (EXPORT) AN TOÀN ---${NC}"
    zpool list
    echo -e "${CYAN}Nhập tên pool (hoặc 'all' để rút hết):${NC}"
    read -r TARGET
    
    if [ -z "$TARGET" ]; then return; fi

    if [ "$TARGET" == "all" ]; then 
        zpool export -a
    else 
        zpool export "$TARGET"
    fi
    
    if [ $? -eq 0 ]; then 
        echo -e "${GREEN}✅ Đã rút an toàn. Bạn có thể tháo ổ cứng.${NC}"
    else
        echo -e "${RED}❌ Không thể rút. Hãy đảm bảo không có ứng dụng nào đang truy cập ổ đĩa.${NC}"
    fi
}

# ==============================================================================
# 4. FORMAT & TẠO POOL (ĐA NỀN TẢNG)
# ==============================================================================
format_disk() {
    echo -e "${RED}🔥 --- FORMAT & TẠO POOL (MẤT DỮ LIỆU) ---${NC}"
    
    local DISK_PATH=""
    local DISK_ID=""

    # 4.1 Liệt kê ổ đĩa theo hệ điều hành
    if [[ "$OS_NAME" == "Darwin" ]]; then
        # macOS
        echo -e "${YELLOW}Danh sách ổ cứng vật lý (External):${NC}"
        diskutil list external physical
        echo -e "${CYAN}Nhập tên ổ đĩa (VD: disk2, disk4):${NC}"
        read -r DISK_ID
        
        # Kiểm tra đầu vào
        if [[ ! "$DISK_ID" =~ ^disk[0-9]+$ ]]; then
            echo -e "${RED}❌ Tên ổ đĩa không hợp lệ (phải là dạng diskX)${NC}"
            return
        fi
        DISK_PATH="/dev/$DISK_ID"
        
    else
        # Linux (Ưu tiên by-id)
        echo -e "${YELLOW}Danh sách ổ cứng (USB/ATA/SCSI/NVMe):${NC}"
        ls -l /dev/disk/by-id/ 2>/dev/null | grep -v "part" | grep "usb\|ata\|scsi\|nvme" | awk '{print $9, "->", $11}'
        
        if [ $? -ne 0 ]; then
            # Fallback nếu không có by-id (ví dụ VM ảo hóa)
            lsblk -d -o NAME,MODEL,SIZE,TYPE,TRAN | grep "disk"
            echo -e "${CYAN}Nhập tên ổ (VD: sdb) hoặc ID (VD: usb-WD...):${NC}"
            read -r TEMP_ID
            if [[ "$TEMP_ID" == sd* || "$TEMP_ID" == nvme* ]]; then
                 DISK_PATH="/dev/$TEMP_ID"
            else
                 DISK_PATH="/dev/disk/by-id/$TEMP_ID"
            fi
            DISK_ID="$TEMP_ID"
        else 
            echo -e "${CYAN}Nhập ID ổ đĩa (VD: usb-WD...):${NC}"
            read -r DISK_ID
            DISK_PATH="/dev/disk/by-id/$DISK_ID"
        fi
    fi

    # 4.2 Kiểm tra tồn tại
    if [ ! -e "$DISK_PATH" ]; then 
        echo -e "${RED}❌ Không tìm thấy thiết bị: $DISK_PATH${NC}"
        return
    fi

    # 4.3 Nhập tên Pool
    echo -e "${CYAN}Nhập tên Pool MỚI (VD: Data_Backup):${NC}"
    read -r POOL_NAME
    if [ -z "$POOL_NAME" ]; then return; fi

    # 4.4 Xác nhận hủy diệt
    echo -e "${RED}⚠️  CẢNH BÁO: TOÀN BỘ DỮ LIỆU TRÊN $DISK_PATH SẼ BỊ XÓA VĨNH VIỄN!${NC}"
    read -p "Bạn có chắc chắn không? (nhập 'yes' để tiếp tục): " confirm
    if [[ "$confirm" != "yes" ]]; then echo "Đã hủy."; return; fi

    # 4.5 Thực hiện Wipe (Xóa sạch partition table)
    echo -e "${YELLOW}🔄 Đang làm sạch ổ đĩa...${NC}"
    
    if [[ "$OS_NAME" == "Darwin" ]]; then
        # macOS Wipe
        # Lần 1: Unmount
        diskutil unmountDisk force "$DISK_PATH" 2>/dev/null
        
        # Xóa partition table
        # Sử dụng bs=1024k để tương thích cả GNU dd (1M) và BSD dd (1m)
        # Bỏ status=none vì BSD dd cũ không hỗ trợ -> dùng 2>/dev/null để ẩn output
        dd if=/dev/zero of="$DISK_PATH" bs=1024k count=10 2>/dev/null
        
        # Đợi disk service cập nhật
        sleep 2
        
        # Lần 2: Unmount lại lần nữa cho chắc (vì sau khi wipe hoặc dd, macOS có thể tự mount lại)
        diskutil unmountDisk force "$DISK_PATH" 2>/dev/null
    else
        # Linux Wipe
        zpool export "$POOL_NAME" 2>/dev/null
        if command -v wipefs &> /dev/null; then
            wipefs --all --force "$DISK_PATH"
        else
            dd if=/dev/zero of="$DISK_PATH" bs=1M count=100 status=none
        fi
        partprobe "$DISK_PATH" 2>/dev/null; sleep 2
    fi

    # 4.6 Tạo Pool
    echo -e "${YELLOW}🛠  Đang tạo Pool ZFS...${NC}"
    
    # Các flag tối ưu chung
    # ashift=12: Tối ưu cho ổ 4K sector
    # compression=lz4: Nén nhanh, hiệu năng cao
    # normalization=formD: Tương thích tên file unicode (quan trọng cho macOS/Linux share)
    # acltype=posixacl: Quyền truy cập chuẩn
    
    if [[ "$OS_NAME" == "Darwin" ]]; then
         # macOS thường cần casesensitivity=insensitive để giống HFS+/APFS
         zpool create -f -o ashift=12 \
            -O compression=lz4 \
            -O normalization=formD \
            -O casesensitivity=insensitive \
            "$POOL_NAME" "$DISK_PATH"
    else
         zpool create -f -o ashift=12 \
            -O compression=lz4 \
            -O xattr=sa \
            -O acltype=posixacl \
            -O normalization=formD \
            "$POOL_NAME" "$DISK_PATH"
    fi

    if [ $? -eq 0 ]; then
        fix_gui_mountpoint "$POOL_NAME"
        echo -e "${GREEN}✅ Tạo thành công pool: $POOL_NAME${NC}"
    else
        echo -e "${RED}❌ Lỗi khi tạo pool.${NC}"
    fi
}

# ==============================================================================
# 5. CÁC TIỆN ÍCH KHÁC
# ==============================================================================
rename_pool() {
    zpool list
    echo -e "${CYAN}Nhập tên hiện tại:${NC}"
    read -r OLD_NAME
    if [ -z "$OLD_NAME" ]; then return; fi
    
    echo -e "${CYAN}Nhập tên MỚI:${NC}"
    read -r NEW_NAME
    if [ -z "$NEW_NAME" ]; then return; fi

    echo -e "${YELLOW}🔄 Đang đổi tên...${NC}"
    zpool export "$OLD_NAME"
    zpool import "$OLD_NAME" "$NEW_NAME"
    
    if [ $? -eq 0 ]; then
        fix_gui_mountpoint "$NEW_NAME"
        echo -e "${GREEN}✅ Đổi tên thành công: $NEW_NAME${NC}"
    else
        echo -e "${RED}❌ Lỗi khi đổi tên.${NC}"
    fi
}

scrub_pool() {
    zpool list
    echo -e "${CYAN}Nhập tên pool để kiểm tra sức khỏe (Scrub):${NC}"
    read -r PNAME
    if [ -n "$PNAME" ]; then
        zpool scrub "$PNAME"
        echo -e "${GREEN}✅ Đã bắt đầu tiến trình Scrub. Dùng 'zpool status' để theo dõi.${NC}"
    fi
}

# ==============================================================================
# 6. QUẢN LÝ SNAPSHOT
# ==============================================================================
snapshot_manager() {
    while true; do
        echo -e "\n${BLUE}--- QUẢN LÝ SNAPSHOT ---${NC}"
        echo "1. 📸 Tạo Snapshot mới"
        echo "2. 📜 Liệt kê Snapshot"
        echo "3. ⏪ Rollback (Khôi phục) Snapshot"
        echo "4. 🗑  Xóa Snapshot"
        echo "0. 🔙 Quay lại Menu chính"
        read -p "Chọn chức năng: " sn_choice

        case $sn_choice in
            1)
                zfs list -t filesystem
                echo -e "${CYAN}Nhập tên Dataset (VD: tank/data):${NC}"
                read -r DS
                echo -e "${CYAN}Nhập tên Snapshot (VD: backup_2023):${NC}"
                read -r TAG
                if [ -n "$DS" ] && [ -n "$TAG" ]; then
                    zfs snapshot "${DS}@${TAG}"
                    [ $? -eq 0 ] && echo -e "${GREEN}✅ Đã tạo: ${DS}@${TAG}${NC}"
                fi
                ;;
            2)
                zfs list -t snapshot
                ;;
            3)
                zfs list -t snapshot
                echo -e "${RED}⚠️  Lưu ý: Dữ liệu mới hơn snapshot sẽ bị mất!${NC}"
                echo -e "${CYAN}Nhập tên đầy đủ (VD: tank/data@backup):${NC}"
                read -r SNAP
                if [ -n "$SNAP" ]; then
                     read -p "Bạn có chắc chắn Rollback về $SNAP không? (yes/no): " confirm
                     if [[ "$confirm" == "yes" ]]; then
                        zfs rollback -r "$SNAP"
                        [ $? -eq 0 ] && echo -e "${GREEN}✅ Đã khôi phục về $SNAP${NC}"
                     fi
                fi
                ;;
            4)
                zfs list -t snapshot
                echo -e "${CYAN}Nhập tên đầy đủ (VD: tank/data@backup):${NC}"
                read -r SNAP
                if [ -n "$SNAP" ]; then
                    read -p "Xóa vĩnh viễn $SNAP? (yes/no): " confirm
                    if [[ "$confirm" == "yes" ]]; then
                        zfs destroy "$SNAP"
                        [ $? -eq 0 ] && echo -e "${GREEN}✅ Đã xóa $SNAP${NC}"
                    fi
                fi
                ;;
            0) return ;;
            *) echo -e "${RED}Không hợp lệ!${NC}" ;;
        esac
    done
}

# ==============================================================================
# MAIN MENU
# ==============================================================================
check_install_zfs

while true; do
    echo -e "\n============================================"
    echo -e "   🦈 OPENZFS MANAGER ($OS_NAME)"
    echo "============================================"
    echo "1. 🔌 Import & Mount (Auto-Fix GUI)"
    echo "2. ⏏️  Eject / Export Pool"
    echo "3. 🛠  Format & Tạo Pool Mới"
    echo "4. 🏥 Scrub Health Check"
    echo "5. 🏷  Đổi tên Pool"
    echo "6. 📊 Zpool Status"
    echo "7. 📸 Quản lý Snapshot"
    echo "0. ❌ Thoát"
    read -p "Chọn chức năng: " choice
    
    case $choice in
        1) scan_and_import ;;
        2) eject_pool ;;
        3) format_disk ;;
        4) scrub_pool ;;
        5) rename_pool ;;
        6) zpool status -v ;; 
        7) snapshot_manager ;;
        0) exit 0 ;;
        *) echo -e "${RED}Không hợp lệ!${NC}" ;;
    esac
done