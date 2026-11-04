# Chạy Flutter + backend và cấu hình cuộc gọi

Mã backend nằm đầy đủ trong thư mục `DuAnCuoiKy_LTDD_API/` của repository Flutter `DuAnCuoiKy_LTDD_Nhom6`. Khi deploy từ repository này, chọn Root Directory `DuAnCuoiKy_LTDD_API`, Dockerfile `./Dockerfile`. Metadata Git của checkout API cũ được giữ trên máy trong thư mục bị Git bỏ qua `.repo-metadata/`. Flutter mặc định trỏ tới URL Render trong `lib/config.dart`; cần triển khai backend mới lên URL đó hoặc truyền `API_BASE_URL` khi chạy.

## 1. Đăng ký trực tiếp

Nhập họ tên, email, số điện thoại, mật khẩu và xác nhận mật khẩu để tạo tài khoản. Ứng dụng đăng nhập sau khi đăng ký thành công, không yêu cầu OTP hoặc cấu hình dịch vụ gửi email. Email và số điện thoại được lưu nhưng không đánh dấu đã xác thực. Backend đã bỏ các endpoint gửi và xác minh OTP.

## 2. Tạo dự án Agora

1. Mở [Agora Console](https://console.agora.io/), tạo dự án cho voice/video calling.
2. Bật xác thực bằng App Certificate; lấy App ID và Primary App Certificate của cùng dự án.
3. Cấu hình `Agora:AppId` và `Agora:AppCertificate` trên backend. Không điền Certificate vào Flutter.

Backend dùng [mã AccessToken2 chính thức của Agora](https://github.com/AgoraIO/Tools/tree/da06bfb83556c597bfcb7db65fa65c975165a130/DynamicKey/AgoraDynamicKey/csharp/src/AgoraIO), lưu trong `DuAnCuoiKy_LTDD_API/Vendor/` cùng giấy phép. Token có thời hạn một giờ, chỉ cấp cho thành viên của cuộc gọi còn hoạt động. Flutter tự xin gia hạn. [Hướng dẫn App Certificate](https://docs.agora.io/en/realtime-media/rtc/reference/console-overview).

## 3. Chạy backend trên máy

Cấu hình Agora nằm trực tiếp trong `DuAnCuoiKy_LTDD_API/appsettings.json`. App ID đã điền theo dự án bạn cung cấp; điền thêm `Agora:AppCertificate`. Không commit file chứa certificate thật. File `DuAnCuoiKy_LTDD_API/appsettings.Development.json` trên máy đã được cập nhật để kết nối SQL Server hosting cũ và giữ JWT secret cho môi trường Development. Trên Render đặt chuỗi kết nối SQL cũ trong biến `ConnectionStrings__DefaultConnection`. Ví dụ bên dưới minh họa SQLite khi muốn chạy một database demo riêng:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=messenger-local.db"
  },
  "JWTKey": {
    "Secret": "THAY_BANG_CHUOI_NGAU_NHIEN_IT_NHAT_32_KY_TU",
    "ValidIssuer": "MessengerCallApi",
    "ValidAudience": "MessengerCallApp"
  },
  "Agora": {
    "AppId": "DIEN_APP_ID_32_KY_TU",
    "AppCertificate": "DIEN_CERTIFICATE_32_KY_TU"
  }
}
```

Chạy từ thư mục dự án Flutter:

```powershell
dotnet run --project DuAnCuoiKy_LTDD_API/MessengerCallApi.csproj --launch-profile http
```

Mở `http://localhost:5111/health` và `http://localhost:5111/swagger` để kiểm tra. Cần .NET 8 runtime. Tài khoản mới đăng ký trực tiếp và đăng nhập bằng email/mật khẩu.

## 4. Chạy Flutter Android

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5111
```

`10.0.2.2` dùng cho Android Emulator. Điện thoại thật cần URL HTTPS public của backend; hai máy đều phải dùng cùng backend. Nếu dùng mạng LAN để debug, cần backend lắng nghe trên `0.0.0.0`, địa chỉ LAN đúng và firewall cho phép. HTTP chỉ được bật trong Android debug manifest; bản release dùng HTTPS.

Máy hiện tại có JDK ở `C:\Program Files\Java\jdk-22`, nhưng Flutter đang trỏ tới Java của Android Studio ở đường dẫn không tồn tại. Nếu `flutter run` báo `JAVA_HOME is set to an invalid directory`, cập nhật đường dẫn JDK cho Flutter rồi chạy lại:

```powershell
flutter config --jdk-dir="C:\Program Files\Java\jdk-22"
flutter doctor -v
```

Lệnh `flutter config` cập nhật cấu hình Flutter trên máy. Có thể kiểm tra build bằng JDK chỉ trong tiến trình hiện tại:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-22'
.\android\gradlew.bat -p android assembleDebug
```

Lần build trên máy này đã chạy qua bước Java nhưng dừng vì chưa cài/chấp nhận giấy phép NDK `28.2.13676358`. Thư mục SDK hiện chỉ có `platform-tools`. Cài Android SDK Command-line Tools, Android SDK Platform 36, Build Tools và NDK (Side by side) `28.2.13676358` bằng Android Studio SDK Manager, sau đó chạy `flutter doctor --android-licenses`, đọc và chấp nhận các điều khoản phù hợp trước khi build lại. Chưa tạo được APK trong lượt sửa này.

Cấp quyền camera/micro khi gọi, bật GPS và cấp quyền vị trí khi chia sẻ. Tin vị trí mở tọa độ trong Google Maps qua đường dẫn HTTPS, không cần Google Maps API key. Đây là chia sẻ vị trí tại thời điểm gửi, không phải theo dõi vị trí liên tục.

## 5. Triển khai backend lên Render

Push những sửa đổi trong Git checkout `DuAnCuoiKy_LTDD_API/` vào repository API của bạn rồi deploy lại dịch vụ hiện có. Dockerfile đã được cập nhật để build cả thư viện Agora. Các biến môi trường cần đặt trên Render:

| Biến | Giá trị |
| --- | --- |
| `ConnectionStrings__DefaultConnection` | Kết nối database bền vững; nếu SQLite, ví dụ `Data Source=/var/data/messenger.db` trên disk đã mount |
| `JWTKey__Secret` | Chuỗi bí mật ngẫu nhiên ít nhất 32 ký tự |
| `JWTKey__ValidIssuer` | `MessengerCallApi` |
| `JWTKey__ValidAudience` | `MessengerCallApp` |
| `Agora__AppId` | App ID |
| `Agora__AppCertificate` | App Certificate |
| `Uploads__WebRoot` | Ví dụ `/var/data/wwwroot` trên disk đã mount |
| `Google__ClientId` | Web OAuth Client ID nếu dùng đăng nhập Google |

Đảm bảo database và thư mục upload nằm trên storage bền vững của môi trường triển khai. Backend hiện dùng `EnsureCreated`, không tự nâng cấp schema database cũ. Thay đổi lần này không thêm bảng. Với nhiều instance cần chia sẻ database, storage upload và Data Protection keys.

## 6. Kiểm thử

```powershell
flutter analyze
flutter test
dotnet test test/backend/MessengerCallApi.Tests.csproj
```

Kiểm thử backend xác minh đăng ký và đăng nhập trực tiếp không có OTP, email/số điện thoại không bị đánh dấu đã xác thực, endpoint OTP đã gỡ, quyền lấy token cuộc gọi, avatar, gửi ảnh và vị trí. Kiểm thử dùng khóa Agora giả, không xác nhận âm thanh/video trên thiết bị thật.

Sau khi điền khóa thật và deploy: dùng hai tài khoản trên hai thiết bị, đăng ký và đăng nhập bằng email/mật khẩu, đăng ảnh Reels, đổi avatar, gửi ảnh hai chiều, gửi vị trí rồi mở Maps, gọi thoại/video, thử tắt/bật mic/camera và kết thúc cuộc gọi từ cả hai phía. Thử từ chối cuộc gọi và mất mạng. Cuộc gọi đến hiện dựa vào SignalR/polling khi ứng dụng đang chạy; chưa tích hợp push notification/CallKit để đánh thức ứng dụng đã bị đóng.

Luồng gửi email đặt lại mật khẩu của backend gốc chưa được triển khai.

## 7. Dịch tin nhắn khi đang chat

Tin nhắn văn bản nhận được trong chat riêng và nhóm có nút **Xem bản dịch**. Nguyên văn được giữ lại. Mặc định dịch sang tiếng Việt; bấm tên ngôn ngữ bên cạnh để chọn tiếng Anh, Nhật, Hàn, Trung, Pháp hoặc Thái. Bấm **Ẩn bản dịch** để thu gọn.

Nút biểu tượng dịch trên thanh tiêu đề bật/tắt **tự dịch tin nhắn đến**. Khi bật, các tin đang hiển thị và tin mới được nhận sẽ tự dịch. Việc tắt tự dịch không xóa bản dịch đã mở. Tính năng không dịch âm thanh trong cuộc gọi.

Ứng dụng dùng Google ML Kit nhận diện ngôn ngữ và dịch trên thiết bị Android. Lần đầu cần Internet để tải mô hình cho cặp ngôn ngữ, có thể mất thời gian hoặc tốn dữ liệu di động. Các lần sau dùng mô hình đã tải. Không cần khóa API dịch hay tài khoản trả phí. [Hướng dẫn Google ML Kit](https://developers.google.com/ml-kit/language/translation/android). Chất lượng bản dịch có thể hạn chế, đặc biệt với câu quá ngắn, tiếng lóng hoặc nhiều ngôn ngữ trong cùng câu. Nếu chưa nhận diện được ngôn ngữ, ứng dụng báo lỗi để thử lại; không tự thay đổi tin nhắn gốc.

Các bài kiểm thử Flutter mô phỏng kết quả dịch để kiểm tra hiển thị, bật tự dịch, thử lại khi lỗi và tránh nhầm bản dịch khi danh sách cập nhật. Chưa kiểm thử mô hình dịch trên điện thoại thật. Dự án hiện có cấu hình Android; các nền tảng khác cần cấu hình native riêng.

## 8. Hai điện thoại ở hai mạng khác nhau

Cả hai máy phải dùng cùng API HTTPS public và hai tài khoản khác nhau. Không dùng localhost, 10.0.2.2 hoặc địa chỉ LAN cho trường hợp hai mạng khác nhau.

Khi kiểm tra trong lượt sửa này, API `https://duancuoiky-ltdd-api.onrender.com` chưa có `/api/Rtc/token`: server vẫn là bản cũ. Cần cập nhật backend lên Render trước khi gọi. Flutter hiện kiểm tra `/api/Rtc/status` trước khi tạo cuộc gọi và báo rõ nếu server cũ hoặc thiếu cấu hình Agora.

1. Cập nhật repository API với mã backend mới. Gói `artifacts/backend-render.zip` được chuẩn bị để đưa mã nguồn lên repository; gói không chứa App Certificate, JWT secret thật hoặc dữ liệu upload. Gói này là mã nguồn, không phải file APK. Những file cấu hình có khóa thật trên máy không được upload công khai.
2. Trong Render → Environment, đặt `Agora__AppId`, `Agora__AppCertificate`, `JWTKey__Secret`, `JWTKey__ValidIssuer=MessengerCallApi`, `JWTKey__ValidAudience=MessengerCallApp`. Điền thêm kết nối database/storage theo mục 5. Hai giá trị Agora phải lấy từ cùng dự án. Mã nguồn trong gói dùng SQLite để khởi động nếu chưa đặt kết nối khác; cần storage bền vững để giữ dữ liệu sau deploy.
3. Deploy lại backend bằng Dockerfile. Mở `/health` để kiểm tra server chạy, mở `/swagger` xác nhận có `GET /api/Rtc/status` và `POST /api/Rtc/token`. Swagger có endpoint không đồng nghĩa khóa Agora đã hợp lệ; cần kiểm tra cuộc gọi thật sau khi cấu hình.
4. Cài cùng bản ứng dụng lên hai máy với cùng địa chỉ API:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=https://duancuoiky-ltdd-api.onrender.com
```

5. Đăng nhập tài khoản A và B, mở ứng dụng trên cả hai máy, cấp quyền micro/camera. A mở chat với B và bấm biểu tượng gọi thoại hoặc video. B chấp nhận cuộc gọi. Thử bật/tắt micro, camera, đổi camera và kết thúc từ từng máy.

SignalR truyền báo hiệu cuộc gọi và tin nhắn; Agora truyền hình ảnh/âm thanh qua Internet. Kiểm thử backend đã mô phỏng hai client SignalR, kiểm tra nhận tin và cuộc gọi, chấp nhận, cấp token cùng kênh nhưng UID khác nhau, kết thúc cuộc gọi và chặn tham gia lại cuộc gọi đã kết thúc. Chưa có kết quả kiểm thử video/audio từ hai điện thoại thật. Cuộc gọi đến hiện yêu cầu ứng dụng đang chạy; chưa có push notification để đánh thức ứng dụng bị đóng.
