# Flutter Messenger Call — chạy bằng API ASP.NET (không còn Firebase)

Bản này giữ nguyên giao diện và luồng của app gốc, chỉ thay lớp dữ liệu:
Firebase Auth / Firestore / Firebase Storage -> REST + JWT + SignalR
tới backend ASP.NET trong thư mục `DuAnCuoiKy_LTDD_API` (xem zip backend riêng).

## 1. Chạy backend trước

Trong Visual Studio hoặc PowerShell, ở thư mục backend:

```
dotnet run --project MessengerCallApi --launch-profile http
```

Phải thấy `Now listening on: http://localhost:5111` và mở
`http://localhost:5111/health` ra `"ok"`, `http://localhost:5111/swagger`
ra đủ API thì mới chạy app. Tắt cửa sổ PowerShell là backend tắt theo.

## 2. Địa chỉ API trong app

Bản này đã trỏ sẵn trong `lib/config.dart` (hàm `apiBaseUrl`) về
link Conveyor https công khai, dùng cho mọi nền tảng (web, emulator,
điện thoại thật):

`https://lastaquacar25.conveyor.cloud/api`

Không dùng localhost, 10.0.2.2 hay IP LAN nữa. Link này chỉ sống khi
máy chạy Visual Studio đang bật và backend đang chạy ở profile http
(localhost:5111); tắt máy / dừng backend là link chết, phải chạy lại
backend rồi lấy lại Internet URL mới trong cửa sổ Conveyor nếu nó đổi.

## 3. Chạy Flutter

```
flutter pub get
flutter run
```

## 4. Luồng test nhanh (2 tài khoản)

1. Đăng ký tài khoản A (tên, email, mật khẩu >= 6 ký tự, SĐT VN
   ví dụ 0912345678) -> vào màn hình Chat.
2. Đăng ký tài khoản B trên máy/emulator khác (hoặc đăng xuất rồi
   đăng ký tài khoản B) -> A và B thấy nhau ở hàng người dùng.
3. A tìm B bằng số điện thoại ở nút + (FriendsScreen) -> Kết bạn,
   B vào FriendsScreen -> Đồng ý.
4. A nhắn tin cho B, B thấy tin (SignalR + poll 3 giây).
5. A gọi thoại/video cho B, B thấy màn hình đổ chuông -> Trả lời,
   Agora dùng callId của backend làm channelId (giữ nguyên App ID
   trong `lib/config.dart`, token Agora để trống như bản gốc).

## 5. Các file đã đổi so với bản gốc

- `lib/config.dart`: thêm `apiBaseUrl`, `signalRHubUrl`.
- `lib/services/api_client.dart` (mới): 1 client REST, gắn JWT.
- `lib/services/auth_service.dart`: register/login/Google/me/logout/
  forgot-password qua API, JWT lưu SharedPreferences.
- `lib/services/chat_service.dart`, `call_service.dart`: REST thay
  Firestore. `friend_service.dart`, `reels_service.dart` (mới).
- `lib/services/realtime_service.dart` (mới): SignalR `/hubs/chat`
  (NewMessage, IncomingCall, CallStatusChanged). Các màn hình vẫn
  poll REST định kỳ (chat 3s, gọi đến 4s, trạng thái cuộc gọi 2s)
  để không sót tin nếu SignalR mất kết nối.
- `lib/main.dart` và các màn hình: bỏ mọi import Firebase/Firestore,
  chuyển Stream sang Future + poll, giao diện giữ nguyên.
- `pubspec.yaml`: bỏ firebase_core/firebase_auth/cloud_firestore/
  firebase_storage, thêm http/shared_preferences/signalr_netcore.
  Giữ google_sign_in (chỉ để lấy idToken gửi lên backend).
- `android/`: bỏ plugin google-services và file google-services.json,
  bỏ thư mục `android_old` trùng lặp.

## 6. Hạn chế còn đúng như backend (không phải lỗi app)

- Quên mật khẩu: backend chưa gửi email thật (chưa có SMTP). Ở
  Development, gọi trực tiếp POST /api/Authenticate/forgot-password
  bằng Swagger sẽ thấy thêm resetToken để demo đổi mật khẩu.
- Đăng nhập Google: backend cần `Google:ClientId` trong
  appsettings.json, nếu chưa điền thì app báo đúng câu đó.
- Agora vẫn ở chế độ testing (token trống) như bản gốc.
