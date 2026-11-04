# Messenger Call API

Backend ASP.NET Core 8 cho ứng dụng Flutter. Thư mục này được lưu đầy đủ cùng mã Flutter trong repository `DuAnCuoiKy_LTDD_Nhom6`.

## Các chức năng

- Đăng ký, đăng nhập bằng email/mật khẩu và Google; không yêu cầu OTP.
- Tin nhắn riêng/nhóm, gửi ảnh, tin nhắn thoại và tọa độ vị trí.
- Đổi avatar, đăng ảnh Reels, kết bạn và lịch sử cuộc gọi.
- SignalR `/hubs/chat` truyền tin nhắn và báo hiệu cuộc gọi.
- `GET /api/Rtc/status` kiểm tra cấu hình Agora; `POST /api/Rtc/token` cấp AccessToken2 cho thành viên cuộc gọi.
- Hai tài khoản dùng cùng App ID/channel nhưng UID riêng; hỗ trợ gia hạn token và chặn lấy token của cuộc gọi đã kết thúc.

Phần xem bản dịch/tự dịch tin nhắn chạy bằng ML Kit trong Flutter, không cần API dịch ở backend này.

## Chạy trên máy

Từ thư mục Flutter:

```powershell
dotnet run --project DuAnCuoiKy_LTDD_API/MessengerCallApi.csproj --launch-profile http
```

`appsettings.Development.json` trên máy đã trỏ tới SQL Server hosting cũ và giữ JWT secret riêng, được Git ignore. Chuỗi kết nối có mật khẩu chỉ lưu trong file này hoặc biến môi trường trên Render. Điền `Agora:AppId` và `Agora:AppCertificate` trong `appsettings.json` để gọi thử; không đưa certificate thật lên GitHub.

Mở `http://localhost:5111/health` và `http://localhost:5111/swagger`. Khi dùng database có sẵn, backend không tự nâng cấp schema vì hiện dùng `EnsureCreated`. Trên Render mới, đặt `ConnectionStrings__DefaultConnection` bằng chuỗi kết nối của database hosting cũ để dùng lại dữ liệu. Chạy ứng dụng với cấu hình này sẽ đọc/ghi trực tiếp database cũ.

## Deploy Render

1. Dùng nhánh `main` của repository `DuAnCuoiKy_LTDD_Nhom6`, nơi có đầy đủ thư mục backend này và `Vendor`.
2. Trong Render chọn repository đó, runtime Docker, Root Directory `DuAnCuoiKy_LTDD_API`, Dockerfile Path `./Dockerfile`, Health Check `/health`. Nếu triển khai từ repository API riêng chứa Dockerfile ngay ở gốc, Root Directory để trống.
3. Giữ các biến cấu hình đang dùng và điền:

| Biến | Giá trị |
| --- | --- |
| `JWTKey__Secret` | Bí mật ngẫu nhiên ít nhất 32 byte |
| `JWTKey__ValidIssuer` | `MessengerCallApi` |
| `JWTKey__ValidAudience` | `MessengerCallApp` |
| `Agora__AppId` | App ID dự án Agora |
| `Agora__AppCertificate` | Certificate của cùng dự án |
| `ConnectionStrings__DefaultConnection` | Kết nối database; demo có thể dùng `Data Source=messenger.db` |
| `Google__ClientId` | Web OAuth Client ID nếu đăng nhập Google |

4. Deploy latest commit. `/health` trả `"ok"`; Swagger phải có hai endpoint `/api/Rtc/status` và `/api/Rtc/token`. Các endpoint RTC yêu cầu JWT của tài khoản đã đăng nhập.
5. Cả hai điện thoại phải cài bản Flutter mới, dùng cùng URL HTTPS và tài khoản khác nhau. Mở ứng dụng trên cả hai máy, cấp camera/micro, gọi từ màn hình chat và chấp nhận ở máy kia.

SQL Server phải truy cập được từ Render nếu chọn SQL Server. SQLite và ảnh trên filesystem tạm của Render có thể mất sau restart/deploy. Dùng database/storage bền vững để giữ dữ liệu; `Uploads__WebRoot` cấu hình thư mục chứa upload nếu có disk.

Cuộc gọi đến hiện dùng SignalR/polling khi ứng dụng đang chạy; chưa có push notification để đánh thức ứng dụng bị đóng. Kiểm thử báo hiệu không thay thế việc thử âm thanh/video trên điện thoại thật.

## Kiểm thử

Từ thư mục Flutter:

```powershell
dotnet test test/backend/MessengerCallApi.Tests.csproj
```

Kiểm thử bao gồm đăng ký/đăng nhập không OTP, gửi ảnh/vị trí, avatar, hai client SignalR trao đổi tin nhắn/cuộc gọi, token cùng kênh với UID khác nhau và chặn truy cập trái quyền.
