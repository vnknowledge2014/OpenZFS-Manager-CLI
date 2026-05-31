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
             
             # Check Suspended
             if zpool list | grep -q "SUSPENDED"; then
                 echo -e "\n${RED}⚠️  PHÁT HIỆN POOL BỊ TREO (SUSPENDED)!${NC}"
                 echo -e "${YELLOW}👉 Hãy chọn chức năng [8] Fix Suspended Pool để xử lý ngay.${NC}"
             fi
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
# 8. XỬ LÝ LỖI SUSPENDED
# ==============================================================================
fix_suspended() {
    echo -e "${BLUE}--- KHẮC PHỤC LỖI SUSPENDED (TREO) ---${NC}"
    
    # Tìm pool bị suspended
    SUSPENDED_POOLS=$(zpool list -H -o name,health | grep "SUSPENDED" | cut -f1)
    
    if [ -z "$SUSPENDED_POOLS" ]; then
        echo -e "${GREEN}✅ Không phát hiện pool nào bị SUSPENDED.${NC}"
        return
    fi
    
    echo -e "${RED}⚠️  PHÁT HIỆN POOL BỊ TREO: ${YELLOW}$SUSPENDED_POOLS${NC}"
    echo -e "Trạng thái này thường do ổ cứng bị ngắt kết nối đột ngột hoặc thiếu điện."
    echo -e "\nCác phương án xử lý:"
    echo "1. 🧹 Clear Errors (Thử kết nối lại và xóa lỗi)"
    echo "2. ⏏️  Force Export (Cưỡng chế rút, có thể cần khởi động lại)"
    echo "0. 🔙 Quay lại"
    read -p "Chọn phương án: " fix_choice
    
    case $fix_choice in
        1)
            for pool in $SUSPENDED_POOLS; do
                echo -e "${CYAN}Đang chạy 'zpool clear $pool'...${NC}"
                zpool clear "$pool"
                if [ $? -eq 0 ]; then
                     echo -e "${GREEN}✅ Đã clear lỗi thành công. Hãy kiểm tra lại kết nối.${NC}"
                else
                     echo -e "${RED}❌ Không thể clear. Có thể ổ cứng vẫn chưa kết nối lại.${NC}"
                fi
            done
            ;;
        2)
            for pool in $SUSPENDED_POOLS; do
                echo -e "${CYAN}Đang chạy 'zpool export -f $pool'...${NC}"
                zpool export -f "$pool"
                if [ $? -eq 0 ]; then
                     echo -e "${GREEN}✅ Đã cưỡng chế export thành công.${NC}"
                else
                     echo -e "${RED}❌ Vẫn bị treo. Bạn CẦN KHỞI ĐỘNG LẠI MÁY để giải phóng kernel.${NC}"
                fi
            done
            ;;
        *) return ;;
    esac
}

# ==============================================================================
# 9. CHECK SMART (TBW)
# ==============================================================================
check_smart_health() {
    echo -e "${BLUE}--- KIỂM TRA SỨC KHỎE Ổ CỨNG (S.M.A.R.T) ---${NC}"
    
    if ! command -v smartctl &> /dev/null; then
        echo -e "${YELLOW}⚠️  Chưa tìm thấy 'smartmontools'.${NC}"
        read -p "Bạn có muốn cài đặt tự động không? (yes/no): " install_choice
        
        if [[ "$install_choice" == "yes" ]]; then
            echo -e "${CYAN}🔄 Đang cài đặt smartmontools...${NC}"
            if [[ "$OS_NAME" == "Darwin" ]]; then
                # macOS: Chạy brew dưới quyền user thật
                if sudo -u "$REAL_USER" command -v brew &> /dev/null; then
                    sudo -u "$REAL_USER" brew install smartmontools
                else
                     echo -e "${RED}❌ Không tìm thấy Homebrew. Vui lòng cài thủ công.${NC}"; return
                fi
            elif [ -f /etc/debian_version ]; then
                 apt update && apt install -y smartmontools
            elif [ -f /etc/arch-release ]; then
                 pacman -Sy --noconfirm smartmontools
            elif [ -f /etc/nixos/configuration.nix ]; then
                 echo -e "${RED}❌ Trên NixOS, hãy thêm 'smartmontools' vào environment.systemPackages và rebuild.${NC}"; return
            else
                 echo -e "${RED}❌ Không hỗ trợ distro này. Hãy cài 'smartmontools' thủ công.${NC}"; return
            fi
            
            # Kiểm tra lại sau khi cài
            if ! command -v smartctl &> /dev/null; then
                echo -e "${RED}❌ Cài đặt thất bại. Vui lòng kiểm tra lại.${NC}"; return
            fi
            echo -e "${GREEN}✅ Cài đặt thành công!${NC}"
            echo -e "--------------------------------------------"
        else
            echo -e "${RED}❌ Bạn đã hủy. Chức năng này cần smartmontools để hoạt động.${NC}"; return
        fi
    fi

    # Liệt kê ổ đĩa để user chọn
    if [[ "$OS_NAME" == "Darwin" ]]; then
        diskutil list external physical
        echo -e "${CYAN}Nhập tên ổ đĩa vật lý (VD: disk2, disk4):${NC}"
    else
        lsblk -d -o NAME,MODEL,SIZE,TYPE
        echo -e "${CYAN}Nhập tên ổ đĩa (VD: sdb):${NC}"
    fi
    
    read -r DISK_ID
    
    local DISK_PATH="/dev/$DISK_ID"
    if [ ! -e "$DISK_PATH" ]; then
        echo -e "${RED}❌ Ổ đĩa không tồn tại!${NC}"
        return
    fi
    
    # 1. Kiểm tra kết nối cơ bản (Timeout 10s)
    echo -e "${YELLOW}🔍 Kiểm tra kết nối (Timeout 10s)...${NC}"
    # Sử dụng perl để timeout (có sẵn trên macOS/Linux)
    if ! perl -e 'alarm shift; exec @ARGV' 10 smartctl -i "$DISK_PATH" &>/dev/null; then
         echo -e "${RED}❌ Lỗi: Ổ đĩa không phản hồi (Timeout).${NC}"
         echo -e "${YELLOW}Nguyên nhân có thể:${NC}"
         echo "1. Ổ cứng đang ngủ sâu (Sleep) -> Hãy thử truy cập file nhẹ xong thử lại."
         echo "2. Controller của Box/Dock USB không hỗ trợ SMART passthrough."
         read -p "Ấn Enter để quay lại..."
         return
    fi

    # 2. Đọc dữ liệu chi tiết
    echo -e "${YELLOW}🔍 Đang đọc dữ liệu chi tiết...${NC}"
    
    # Lấy toàn bộ output (thêm -T permissive để bỏ qua lỗi nhỏ)
    SMART_OUTPUT=$(smartctl -a -T permissive "$DISK_PATH" 2>&1)
    
    # Lọc thông tin quan trọng
    FILTERED_OUTPUT=$(echo "$SMART_OUTPUT" | grep -E "Model Family|Device Model|User Capacity|Total_LBAs_Written|Data Units Written|Percentage Used|Power_On_Hours|Media_and_Data_Integrity|SMART overall-health self-assessment test result")
    
    if [ -n "$FILTERED_OUTPUT" ]; then
        echo -e "${GREEN}✅ KẾT QUẢ PHÂN TÍCH:${NC}"
        echo "$FILTERED_OUTPUT"
    else
        echo -e "${RED}⚠️  Không lọc được thông số tiêu chuẩn. Hiển thị toàn bộ output:${NC}"
        echo "---------------------------------------------------"
        echo "$SMART_OUTPUT"
        echo "---------------------------------------------------"
        echo -e "${YELLOW}Gợi ý: Nếu output báo lỗi 'Operation not supported', ổ cứng box/dock của bạn có thể không hỗ trợ SMART qua USB.${NC}"
    fi
    
    echo -e "\n${GREEN}💡 GIẢI THÍCH:${NC}"
    echo "   - Percentage Used: Tuổi thọ đã dùng (100% là hỏng/hết bảo hành)."
    echo "   - Data Units Written: Lượng dữ liệu đã ghi (TBW - chỉ NVMe)."
    echo "   - Media Integrity: Lỗi vật lý (phải bằng 0)."
    read -p "Ấn Enter để quay lại..."
}

# ==============================================================================
# 10. SSD TRIM
# ==============================================================================
trim_pool() {
    echo -e "${BLUE}--- SSD TRIM (TỐI ƯU HIỆU NĂNG) ---${NC}"
    zpool list -o name,autotrim,health
    echo -e "\n${YELLOW}Ghi chú: 'autotrim=on' nghĩa là ZFS sẽ tự động TRIM ngầm.${NC}"
    echo -e "${CYAN}Nhập tên pool (VD: Lexar):${NC}"
    read -r PNAME
    
    if [ -z "$PNAME" ]; then return; fi
    
    echo "1. ⚡ Chạy TRIM thủ công ngay (Manual Run)"
    echo "2. 🔄 Bật/Tắt tự động TRIM (Auto-TRIM)"
    read -p "Chọn: " tr_choice
    
    case $tr_choice in
        1)
            echo -e "${YELLOW}🔄 Đang gửi lệnh TRIM...${NC}"
            zpool trim "$PNAME"
            echo -e "${GREEN}✅ Đã gửi lệnh. Kiểm tra tiến độ tại mục [6] Status.${NC}"
            ;;
        2)
            CUR_VAL=$(zpool get -H -o value autotrim "$PNAME")
            if [ "$CUR_VAL" == "on" ]; then
                zpool set autotrim=off "$PNAME"
                echo -e "${RED}🛑 Đã TẮT Auto-TRIM cho $PNAME.${NC}"
            else
                zpool set autotrim=on "$PNAME"
                echo -e "${GREEN}✅ Đã BẬT Auto-TRIM cho $PNAME.${NC}"
            fi
            ;;
    esac
    read -p "Ấn Enter để tiếp tục..."
}

# ==============================================================================
# 11. DATASET MANAGER
# ==============================================================================
dataset_manager() {
    while true; do
        echo -e "\n${BLUE}--- QUẢN LÝ DATASET / THƯ MỤC ---${NC}"
        echo "1. 📂 Tạo Dataset Mới (New Folder)"
        echo "2. 🗜️  Cấu hình Nén (Compression)"
        echo "3. 💾 Giới hạn Dung lượng (Quota)"
        echo "4. 📍 Xem Danh sách Dataset"
        echo "0. 🔙 Quay lại"
        read -p "Chọn chức năng: " ds_choice
        
        case $ds_choice in
            1)
                zfs list -t filesystem
                echo -e "${CYAN}Nhập tên Dataset Mới (VD: tank/Phim):${NC}"
                read -r NEW_DS
                if [ -n "$NEW_DS" ]; then
                    zfs create "$NEW_DS"
                    [ $? -eq 0 ] && echo -e "${GREEN}✅ Đã tạo: $NEW_DS${NC}"
                fi
                ;;
            2)
                zfs list -t filesystem
                echo -e "${CYAN}Nhập tên Dataset cần chỉnh (VD: tank/Phim):${NC}"
                read -r DS_NAME
                echo -e "${CYAN}Chọn chuẩn nén (lz4=Chuẩn, zstd=Mạnh, off=Tắt):${NC}"
                read -r COMP_ALGO
                if [ -n "$DS_NAME" ] && [ -n "$COMP_ALGO" ]; then
                    zfs set compression="$COMP_ALGO" "$DS_NAME"
                    echo -e "${GREEN}✅ Đã set compression=$COMP_ALGO cho $DS_NAME${NC}"
                fi
                ;;
            3)
                zfs list -H -o name,quota,used
                echo -e "${CYAN}Nhập tên Dataset (VD: tank/TimeMachine):${NC}"
                read -r DS_NAME
                echo -e "${CYAN}Nhập giới hạn (VD: 500G, 1T, none=Bỏ giới hạn):${NC}"
                read -r QUOTA_SIZE
                if [ -n "$DS_NAME" ] && [ -n "$QUOTA_SIZE" ]; then
                    zfs set quota="$QUOTA_SIZE" "$DS_NAME"
                    echo -e "${GREEN}✅ Đã set quota=$QUOTA_SIZE cho $DS_NAME${NC}"
                fi
                ;;
            4)
                zfs list -o name,used,avail,compressratio,mountpoint
                read -p "Ấn Enter để tiếp tục..."
                ;;
            0) return ;;
            *) echo -e "${RED}Không hợp lệ!${NC}" ;;
        esac
    done
}

# ==============================================================================
# 12. REPLICATION MANAGER
# ==============================================================================
replication_manager() {
    echo -e "${BLUE}--- SAO CHÉP POOL VÀ DATASET (REPLICATION) ---${NC}"
    echo "1. 👯 Clone toàn bộ Pool A -> Pool B (Backup)"
    echo "2. 📤 Gửi Snapshot cụ thể"
    echo "0. 🔙 Quay lại"
    read -p "Chọn chức năng: " rep_choice
    
    case $rep_choice in
        1)
            zpool list
            echo -e "${CYAN}Nhập Pool NGUỒN (VD: Lexar):${NC}"
            read -r SRC
            echo -e "${CYAN}Nhập Pool ĐÍCH (VD: SEAGATE):${NC}"
            read -r DST
            
            if [ -z "$SRC" ] || [ -z "$DST" ]; then return; fi
            if [ "$SRC" == "$DST" ]; then echo -e "${RED}Nguồn và đích phải khác nhau!${NC}"; return; fi
            
            echo -e "${RED}⚠️  CẢNH BÁO: Dữ liệu trên $DST/backup_$SRC sẽ bị ghi đè!${NC}"
            read -p "Tiếp tục? (yes/no): " confirm
            if [[ "$confirm" != "yes" ]]; then return; fi
            
            # Tạo snapshot tạm
            SNAP_NAME="repl_$(date +%s)"
            zfs snapshot -r "$SRC@$SNAP_NAME"
            
            echo -e "${YELLOW}🚀 Đang gửi dữ liệu... (Có thể rất lâu)${NC}"
            # Send stream
            zfs send -R "$SRC@$SNAP_NAME" | zfs receive -F "$DST/backup_$SRC"
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Backup hoàn tất tại $DST/backup_$SRC${NC}"
                # Xóa snapshot tạm để tiết kiệm chỗ
                zfs destroy -r "$SRC@$SNAP_NAME"
            else
                echo -e "${RED}❌ Lỗi backup.${NC}"
            fi
            ;;
        2)
            zfs list -t snapshot
            echo -e "${CYAN}Nhập snapshot cần gửi (VD: tank/data@snap1):${NC}"
            read -r SNAP
            echo -e "${CYAN}Nhập dataset đích (VD: backup_pool/restore):${NC}"
            read -r DEST_DS
            
            if [ -n "$SNAP" ] && [ -n "$DEST_DS" ]; then
                 zfs send "$SNAP" | zfs receive "$DEST_DS"
                 echo -e "${GREEN}✅ Đã gửi xong.${NC}"
            fi
            ;;
        *) return ;;
    esac
}

# ==============================================================================
# 14. MIGRATION ASSISTANT (RSYNC) - Non-ZFS ↔ ZFS
# ==============================================================================
migration_assistant() {
    # Fix Tab completion for macOS/older Bash/Termux
    bind '"\t":complete' 2>/dev/null
    bind '"\C-i":complete' 2>/dev/null
    bind "set completion-ignore-case on" 2>/dev/null
    bind "set show-all-if-ambiguous on" 2>/dev/null
    bind "set editing-mode emacs" 2>/dev/null

    echo -e "\n${BLUE}--- 🚚 MIGRATION ASSISTANT ---${NC}"
    echo "Copy dữ liệu giữa ZFS và ổ ngoài (ext4/NTFS/ExFAT/APFS)."
    echo -e "${YELLOW}💡 Tip: ZFS ↔ ZFS hãy dùng Menu [12] Replication (nhanh hơn).${NC}\n"
    echo "1. 📥 Import: Non-ZFS → ZFS"
    echo "2. 📤 Export: ZFS → Non-ZFS"
    echo "0. 🔙 Quay lại"
    read -p "Chọn: " direction
    
    case $direction in
        1)  # IMPORT
            echo -e "${CYAN}Đường dẫn NGUỒN (Non-ZFS), VD: /media/usb/file.zip${NC}"
            read -e -r SRC_PATH
            echo -e "\n${YELLOW}📂 Dataset ZFS:${NC}"
            zfs list -o name,mountpoint
            echo -e "${CYAN}Đường dẫn ĐÍCH (ZFS), VD: /Volumes/Lexar/Backup${NC}"
            read -e -r DST_PATH
            ;;
        2)  # EXPORT
            echo -e "\n${YELLOW}📂 Dataset ZFS:${NC}"
            zfs list -o name,mountpoint
            echo -e "${CYAN}Đường dẫn NGUỒN (ZFS), VD: /Volumes/Lexar/file.zip${NC}"
            read -e -r SRC_PATH
            echo -e "${CYAN}Đường dẫn ĐÍCH (Non-ZFS), VD: /home/user/Backup${NC}"
            read -e -r DST_PATH
            ;;
        0|"") return ;;
        *) echo -e "${RED}Không hợp lệ!${NC}"; return ;;
    esac
    
    # Trim quotes from drag-drop
    SRC_PATH=$(echo "$SRC_PATH" | sed "s/^['\"]//;s/['\"]$//;s/ *$//")
    DST_PATH=$(echo "$DST_PATH" | sed "s/^['\"]//;s/['\"]$//;s/ *$//")
    
    # Validate paths
    if [ ! -e "$SRC_PATH" ]; then
        echo -e "${RED}❌ Nguồn không tồn tại: $SRC_PATH${NC}"; return
    fi
    if [ ! -d "$DST_PATH" ]; then
        echo -e "${RED}❌ Đích không tồn tại: $DST_PATH${NC}"; return
    fi
    
    # Confirm and execute
    echo -e "\n${YELLOW}⚠️  COPY: ${CYAN}$SRC_PATH${NC} → ${CYAN}$DST_PATH${NC}"
    read -p "Tiếp tục? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && { echo -e "${RED}Đã hủy.${NC}"; return; }
    
    echo -e "\n${GREEN}🚀 Rsync -avhP ...${NC}\n"
    rsync -avhP "$SRC_PATH" "$DST_PATH"
    
    [ $? -eq 0 ] && echo -e "\n${GREEN}✅ Hoàn tất!${NC}" || echo -e "\n${RED}❌ Có lỗi!${NC}"
    read -p "Enter để tiếp tục..."
}

# ==============================================================================
# 13. DATA REPAIR (THAY ĐĨA HỎNG)
# ==============================================================================
repair_manager() {
    echo -e "${RED}--- THAY THẾ Ổ ĐĨA HỎNG (REPAIR) ---${NC}"
    zpool status
    
    echo -e "\n${YELLOW}Hướng dẫn:${NC}"
    echo "1. Tìm ID ổ cứng bị lỗi (thường hiện là UNAVAIL hoặc chuỗi số dài)."
    echo "2. Cắm ổ cứng mới vào máy."
    echo "3. Lấy ID ổ cứng mới (VD: /dev/disk4 hoặc /dev/sdb)."
    echo -e "--------------------------------------------------------"
    
    echo -e "${CYAN}Nhập tên Pool (VD: data):${NC}"
    read -r POOL
    if [ -z "$POOL" ]; then return; fi
    
    echo -e "${CYAN}Nhập ID ổ HỎNG cũ (VD: 123456789... hoặc ata-WD...):${NC}"
    read -r OLD_DISK
    
    echo -e "${CYAN}Nhập đường dẫn ổ MỚI (VD: /dev/disk4 hoặc /dev/disk/by-id/...):${NC}"
    read -r NEW_DISK
    
    if [ -n "$OLD_DISK" ] && [ -n "$NEW_DISK" ]; then
        echo -e "${YELLOW}🔄 Đang thay thế... Quá trình Resilver sẽ bắt đầu.${NC}"
        zpool replace "$POOL" "$OLD_DISK" "$NEW_DISK"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Lệnh replace thành công!${NC}"
            echo -e "${BLUE}Dùng 'zpool status' để theo dõi tiến độ Resilver.${NC}"
        else
            echo -e "${RED}❌ Lỗi replace. Kiểm tra lại ID ổ đĩa.${NC}"
        fi
    fi
    read -p "Ấn Enter để tiếp tục..."
}

# ==============================================================================
# 15. QUẢN LÝ BỘ NHỚ CACHE ZFS (ARC LIMIT)
# ==============================================================================
manage_arc_limit() {
    echo -e "${BLUE}--- QUẢN LÝ BỘ NHỚ CACHE ZFS (ARC LIMIT) ---${NC}"
    
    # Hiển thị thông tin RAM vật lý & ARC
    if [[ "$OS_NAME" == "Darwin" ]]; then
        PHYS_MEM_BYTES=$(sysctl -n hw.memsize)
        PHYS_MEM_GB=$((PHYS_MEM_BYTES / 1073741824))
        CURRENT_ARC_BYTES=$(sysctl -n vfs.zfs.arc.max 2>/dev/null || echo "0")
    else
        PHYS_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        PHYS_MEM_GB=$((PHYS_MEM_KB / 1048576))
        if [ -f /sys/module/zfs/parameters/zfs_arc_max ]; then
            CURRENT_ARC_BYTES=$(cat /sys/module/zfs/parameters/zfs_arc_max)
        else
            CURRENT_ARC_BYTES="0"
        fi
    fi
    
    CURRENT_ARC_GB=$((CURRENT_ARC_BYTES / 1073741824))
    
    echo -e "   - Tổng dung lượng RAM vật lý: ${GREEN}${PHYS_MEM_GB} GB${NC}"
    if [ "$CURRENT_ARC_BYTES" -eq 0 ]; then
        echo -e "   - Giới hạn ARC hiện tại: ${YELLOW}Mặc định hệ thống${NC}"
    else
        echo -e "   - Giới hạn ARC hiện tại: ${GREEN}${CURRENT_ARC_GB} GB${NC} (${CURRENT_ARC_BYTES} bytes)"
    fi
    echo -e "--------------------------------------------------------"
    echo -e "Nhập giới hạn RAM tối đa mới cho ARC (đơn vị GB, VD: 8, 12, 16):"
    echo -e "*(Nhập '0' hoặc 'none' để đưa về mặc định của hệ thống)*"
    read -r NEW_LIMIT
    
    if [ -z "$NEW_LIMIT" ]; then return; fi
    
    local NEW_LIMIT_BYTES=0
    if [[ "$NEW_LIMIT" =~ ^[0-9]+$ ]]; then
        if [ "$NEW_LIMIT" -eq 0 ]; then
            NEW_LIMIT_BYTES=0
        else
            NEW_LIMIT_BYTES=$((NEW_LIMIT * 1073741824))
        fi
    elif [[ "$NEW_LIMIT" == "none" ]]; then
        NEW_LIMIT_BYTES=0
    else
        echo -e "${RED}❌ Lỗi: Giới hạn không hợp lệ. Phải là một số nguyên dương.${NC}"
        read -p "Ấn Enter để quay lại..."
        return
    fi
    
    echo -e "${YELLOW}🔄 Đang áp dụng cấu hình mới...${NC}"
    
    if [[ "$OS_NAME" == "Darwin" ]]; then
        # macOS
        sysctl -w vfs.zfs.arc.max="$NEW_LIMIT_BYTES"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Đã áp dụng tức thì thành công!${NC}"
            
            # Ghi vào cấu hình để giữ sau reboot
            read -p "Bạn có muốn lưu vĩnh viễn cấu hình này sau khi khởi động lại máy? (yes/no): " save_confirm
            if [[ "$save_confirm" == "yes" ]]; then
                mkdir -p /etc/zfs
                if [ "$NEW_LIMIT_BYTES" -eq 0 ]; then
                    sed -i '' '/vfs.zfs.arc.max/d' /etc/zfs/zfs.conf 2>/dev/null || true
                    echo -e "${GREEN}✅ Đã xóa giới hạn vĩnh viễn trong /etc/zfs/zfs.conf (sử dụng mặc định).${NC}"
                else
                    if [ -f /etc/zfs/zfs.conf ]; then
                        sed -i '' '/vfs.zfs.arc.max/d' /etc/zfs/zfs.conf 2>/dev/null || true
                    fi
                    echo "vfs.zfs.arc.max=$NEW_LIMIT_BYTES" >> /etc/zfs/zfs.conf
                    echo -e "${GREEN}✅ Đã lưu cấu hình vĩnh viễn vào /etc/zfs/zfs.conf!${NC}"
                fi
            fi
        else
            echo -e "${RED}❌ Lỗi khi áp dụng sysctl vfs.zfs.arc.max.${NC}"
        fi
        
    else
        # Linux (Ubuntu, NixOS, etc.)
        if [ -f /etc/nixos/configuration.nix ]; then
            echo -e "${YELLOW}ℹ️  Trên NixOS, cấu hình động có thể không được duy trì sau khi rebuild.${NC}"
            echo -e "Để cấu hình vĩnh viễn trên NixOS, hãy thêm cấu hình này vào ${CYAN}/etc/nixos/configuration.nix${NC}:"
            if [ "$NEW_LIMIT_BYTES" -eq 0 ]; then
                echo -e "${CYAN}  boot.extraModprobeConfig = \"options zfs zfs_arc_max=0\";${NC}"
            else
                echo -e "${CYAN}  boot.extraModprobeConfig = \"options zfs zfs_arc_max=$NEW_LIMIT_BYTES\";${NC}"
            fi
            echo -e "${YELLOW}Sau đó chạy: sudo nixos-rebuild switch${NC}"
        fi
        
        # Áp dụng trực tiếp vào sysfs
        if [ -f /sys/module/zfs/parameters/zfs_arc_max ]; then
            echo "$NEW_LIMIT_BYTES" > /sys/module/zfs/parameters/zfs_arc_max
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Đã áp dụng tức thì thành công!${NC}"
                
                # Cấu hình vĩnh viễn cho Debian/Ubuntu
                if [ ! -f /etc/nixos/configuration.nix ]; then
                    read -p "Bạn có muốn lưu vĩnh viễn cấu hình này sau khi khởi động lại máy? (yes/no): " save_confirm
                    if [[ "$save_confirm" == "yes" ]]; then
                        mkdir -p /etc/modprobe.d
                        if [ "$NEW_LIMIT_BYTES" -eq 0 ]; then
                            sed -i '/zfs_arc_max/d' /etc/modprobe.d/zfs.conf 2>/dev/null || true
                            echo -e "${GREEN}✅ Đã xóa giới hạn vĩnh viễn trong /etc/modprobe.d/zfs.conf.${NC}"
                        else
                            if [ -f /etc/modprobe.d/zfs.conf ]; then
                                    sed -i '/zfs_arc_max/d' /etc/modprobe.d/zfs.conf 2>/dev/null || true
                            fi
                            echo "options zfs zfs_arc_max=$NEW_LIMIT_BYTES" >> /etc/modprobe.d/zfs.conf
                            echo -e "${GREEN}✅ Đã lưu cấu hình vĩnh viễn vào /etc/modprobe.d/zfs.conf!${NC}"
                        fi
                    fi
                fi
            else
                echo -e "${RED}❌ Lỗi khi ghi vào /sys/module/zfs/parameters/zfs_arc_max.${NC}"
            fi
        else
            echo -e "${RED}❌ Không tìm thấy module ZFS hoặc thông số zfs_arc_max.${NC}"
        fi
    fi
    
    read -p "Ấn Enter để tiếp tục..."
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
    echo "8. 🚑 Fix Suspended Pool"
    echo "9. 🌡️  Check SSD Health (TBW)"
    echo "10. ⚡ SSD TRIM (Optimize Performance)"
    echo "11. 🗂️  Dataset Manager (Create/Limit/Compress)"
    echo "12. 🚀 Replication (Copy Pool A -> Pool B)"
    echo "13. 🛠️  Replace Bad Disk (Repair)"
    echo "14. 🚚 Migration Assistant (Rsync/ZFS)"
    echo "15. 🧠 Quản lý RAM Cache ZFS (ARC Limit)"
    echo "0. ❌ Thoát"
    read -p "Chọn chức năng: " choice
    
    case $choice in
        1) scan_and_import ;;
        2) eject_pool ;;
        3) format_disk ;;
        4) scrub_pool ;;
        5) rename_pool ;;
        6) zpool status -v -t ;; 
        7) snapshot_manager ;;
        8) fix_suspended ;;
        9) check_smart_health ;;
        10) trim_pool ;;
        11) dataset_manager ;;
        12) replication_manager ;;
        13) repair_manager ;;
        14) migration_assistant ;;
        15) manage_arc_limit ;;
        0) exit 0 ;;
        *) echo -e "${RED}Không hợp lệ!${NC}" ;;
    esac
done