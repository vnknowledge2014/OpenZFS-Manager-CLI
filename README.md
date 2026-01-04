# 🦈 OpenZFS Manager (Cross-Platform)

Bộ công cụ quản lý ZFS đơn giản, hiệu quả, hỗ trợ đa nền tảng (macOS, Linux, Windows) và đa Shell.

## 🌟 Tính Năng Chính

Script cung cấp menu trực quan để thực hiện các tháo tác ZFS phổ biến:

1.  **🔌 Import & Mount (Auto-Fix GUI)**: Tự động quét tìm Pool, Import và mount vào vị trí chuẩn (`/Volumes` trên macOS hoặc `/media/$USER` trên Linux) để hiển thị ngay lập tức trong Finder/File Manager.
2.  **⏏️ Eject / Export Pool**: Ngắt kết nối Pool an toàn trước khi rút ổ cứng.
3.  **🛠 Format & Tạo Pool Mới**: Hỗ trợ format ổ cứng vật lý và tạo ZFS Pool mới với các thông số tối ưu (`lz4`, `ashift=12`, `normalization=formD`...).
4.  **🏥 Scrub Health Check**: Kiểm tra toàn vẹn dữ liệu (Scrub) để phát hiện lỗi bit-rot.
5.  **🏷 Đổi tên Pool**: Đổi tên Pool và tự động cập nhật lại mountpoint để tránh lỗi metadata.
6.  **📊 Zpool Status**: Xem trạng thái chi tiết của các ổ đĩa và Pool.
7.  **📸 Quản lý Snapshot**:
    *   Tạo Snapshot tức thời (Instant Checkpoint).
    *   Liệt kê danh sách Snapshot.
    *   **Rollback**: Khôi phục dữ liệu về thời điểm cũ chỉ trong vài giây.
    *   Xóa Snapshot không cần thiết.

8.  **🚑 Fix Suspended Pool**:
    *   Tự động phát hiện pool bị treo (do ngắt kết nối/lỏng cáp).
    *   Hỗ trợ **Clear Errors** (kết nối lại) hoặc **Force Export** (cưỡng chế ngắt) để cứu hệ thống khỏi bị treo.
9.  **🌡️ Check SSD Health (TBW)**:
    *   Đọc thông số S.M.A.R.T của ổ cứng (yêu cầu `smartmontools`).
    *   Theo dõi: Tuổi thọ (Percentage Used), Tổng ghi (TBW), và Lỗi vật lý.
    *   **Auto-Install**: Tự động cài đặt tool trên macOS/Linux nếu thiếu.
10. **⚡ SSD TRIM**:
    *   Tối ưu hóa hiệu năng cho ổ SSD (Manual & Auto-TRIM).
    *   Theo dõi tiến độ TRIM theo thời gian thực.
11. **🗂️ Dataset Manager**:
    *   Tạo Dataset con (VD: `tank/Data`, `tank/Phim`).
    *   Cấu hình nén (**Compression**): `lz4` (default), `zstd` (mạnh), `off` (video).
    *   Cấu hình giới hạn (**Quota**): Giới hạn dung lượng thư mục (VD: 500G).
12. **🚀 Replication (Backup)**:
    *   **Clone Pool**: Sao chép toàn bộ dữ liệu từ Pool A -> Pool B chỉ với 1 cú click.
    *   Hỗ trợ gửi Snapshot cụ thể.
13. **🛠️ Replace Bad Disk**: Hướng dẫn thay thế ổ cứng hỏng (Resilver) từng bước một.

---

## 💻 Hỗ Trợ Đa Nền Tảng

### 1. macOS & Linux (Ubuntu/Debian/NixOS)
Sử dụng file: `zfs_manager.sh`

*   **Tương thích Shell**: Bash, Zsh, Fish, Nushell (Script tự động chuyển sang môi trường Bash khi chạy).
*   **Yêu cầu**: `sudo`. Script sẽ tự động phát hiện và hướng dẫn cài đặt OpenZFS nếu chưa có:
    *   **macOS**: Cài qua Homebrew (`brew install openzfs`). Tự động xử lý biến môi trường `PATH`.
    *   **Ubuntu/Debian**: Cài qua APT (`apt install zfsutils-linux`).
    *   **NixOS**: Hướng dẫn thêm config vào `configuration.nix`.

**Cách dùng:**
```bash
# Cấp quyền thực thi (lần đầu)
chmod +x zfs_manager.sh

# Chạy script
sudo ./zfs_manager.sh
```

### 2. Windows
Sử dụng file: `zfs_manager.ps`

*   **Yêu cầu**: PowerShell (Run as Administrator) và đã cài đặt [OpenZFS on Windows](https://github.com/openzfsonwindows/openzfs/releases).
*   **Tính năng**: Import, Export, Format, Rename, Scrub, Status.

**Cách dùng:**
Chuột phải vào file `zfs_manager.ps` > **Run with PowerShell**.

---

## ⚙️ Cấu Hình Tối Ưu ZFS

Khi tạo Pool mới, script tự động áp dụng các thiết lập tối ưu (Best Practices):
*   `ashift=12`: Tối ưu hiệu năng cho ổ cứng 4K Sector (HDD hiện đại & SSD).
*   `compression=lz4`: Nén dữ liệu nhẹ, tăng tốc độ đọc/ghi (mặc định của OpenZFS).
*   `normalization=formD`: Đảm bảo hiển thị đúng tên file tiếng Việt/Unicode giữa macOS và Linux.
*   `casesensitivity=insensitive` (macOS Only): Giúp Finder hoạt động mượt mà như HFS+/APFS.
*   `acltype=posixacl` / `xattr=sa` (Linux/Windows): Hỗ trợ phân quyền file chuẩn.

---

## ⚠️ Lưu Ý Quan Trọng
*   **Dữ liệu**: Chức năng **Format** và **Rollback** sẽ thay đổi dữ liệu vĩnh viễn. Hãy cẩn thận khi sử dụng.
*   **macOS**: Lần đầu cài đặt OpenZFS, bạn cần vào **System Settings > Privacy & Security** để **Approve** kernel extension và khởi động lại máy.

---
*Script được thiết kế để đơn giản hóa thao tác dòng lệnh cho người dùng ZFS.*
