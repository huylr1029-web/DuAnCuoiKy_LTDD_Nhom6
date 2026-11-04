using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Data;
using MessengerCallApi.Models;

namespace MessengerCallApi.Controllers;

// Bao mat tai khoan: sau khi dang ky, danh sach tai khoan chi hien voi
// BAN BE da chap nhan ket ban, khong hien voi nguoi la.
// - GET api/Users chi tra ban be da accepted (trang chu chi thay ban be).
// - GET api/Users/{id} chi tra khi la ban be (hoac chinh minh), neu khong
//   phai ban be thi tra 404 giong nhu khong ton tai.
// - Ket ban moi qua QR hoac qua SDT: nguoi quet QR da co uid trong ma QR
//   nen goi POST FriendRequests {receiverId} truc tiep; nguoi biet dung SDT
//   thi tim bang by-phone (chi can biet dung SDT moi tim thay, khong duyet
//   duoc danh sach). Theo yeu cau moi nhat cua user, tim SDT duoc mo lai,
//   chap nhan danh doi: ai biet SDT cung tim thay tai khoan de gui loi moi.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class UsersController : ControllerBase
{
    private readonly UserManager<AppUser> _users;
    private readonly ApplicationDbContext _db;
    private readonly IWebHostEnvironment _env;

    public UsersController(UserManager<AppUser> users, ApplicationDbContext db, IWebHostEnvironment env)
    {
        _users = users;
        _db = db;
        _env = env;
    }

    private string AbsoluteUrl(string relativePath) =>
        $"{Request.Scheme}://{Request.Host}/{relativePath.Replace('\\', '/')}";

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    private static UserDto ToDto(AppUser u) =>
        new(u.Id, u.Name, u.Email ?? "", u.PhoneNumber, u.Online, u.LastSeen, u.AvatarUrl);

    private async Task<bool> IsFriend(string otherId)
    {
        if (otherId == MyId) return true;
        return await _db.FriendRequests.AnyAsync(r =>
            r.Status == "accepted" &&
            ((r.SenderId == MyId && r.ReceiverId == otherId) ||
             (r.SenderId == otherId && r.ReceiverId == MyId)));
    }

    private async Task<List<string>> FriendIds()
    {
        var requests = await _db.FriendRequests
            .Where(r => r.Status == "accepted" && (r.SenderId == MyId || r.ReceiverId == MyId))
            .ToListAsync();
        return requests.Select(r => r.SenderId == MyId ? r.ReceiverId : r.SenderId).Distinct().ToList();
    }

    // GET api/Users: chi ban be da accepted, online len truoc.
    [HttpGet]
    public async Task<IActionResult> All()
    {
        var friendIds = await FriendIds();
        var list = await _users.Users
            .Where(u => friendIds.Contains(u.Id))
            .OrderByDescending(u => u.Online)
            .ThenBy(u => u.Name)
            .ToListAsync();
        return Ok(list.Select(ToDto));
    }

    // GET api/Users/{id}: chi ban be / chinh minh moi xem duoc.
    [HttpGet("{id}")]
    public async Task<IActionResult> One(string id)
    {
        if (!await IsFriend(id)) return NotFound(new { message = "Không tìm thấy người dùng" });
        var user = await _users.FindByIdAsync(id);
        if (user == null) return NotFound(new { message = "Không tìm thấy người dùng" });
        return Ok(ToDto(user));
    }

    // GET api/Users/by-phone?phone=0912345678
    // Tim dung SDT de ket ban moi (mo lai theo yeu cau moi nhat).
    // Khong yeu cau phai la ban be truoc, vi muc dich la tim nguoi la
    // de gui loi moi. Chi tra 1 tai khoan khac minh, khong tra danh sach.
    [HttpGet("by-phone")]
    public async Task<IActionResult> ByPhone([FromQuery] string phone)
    {
        var normalized = PhoneHelper.Normalize(phone);
        if (normalized == null)
            return BadRequest(new { message = "Số điện thoại Việt Nam không hợp lệ (ví dụ 0912345678)" });

        var found = await _users.Users
            .Where(u => u.PhoneNumber == normalized && u.Id != MyId)
            .Take(2)
            .ToListAsync();
        if (found.Count == 0) return NotFound(new { message = "Không tìm thấy tài khoản khác với số điện thoại này." });
        return Ok(ToDto(found[0]));
    }

    // PUT api/Users/me: doi ten hien thi / biet danh cua chinh minh.
    // Chi doi duoc ten cua minh, khong doi email / so dien thoai.
    // Ten moi se hien o danh sach user, loi moi ket ban moi va
    // cac doan chat moi mo (doan chat cu giu ten snapshot luc tao).
    [HttpPut("me")]
    public async Task<IActionResult> UpdateMe([FromBody] UpdateNameRequest req)
    {
        var name = req.Name?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(name) || name.Length > 100)
            return BadRequest(new { message = "Tên hiển thị không được để trống và tối đa 100 ký tự" });

        var user = await _users.FindByIdAsync(MyId);
        if (user == null) return Unauthorized();
        user.Name = name;
        await _users.UpdateAsync(user);
        return Ok(ToDto(user));
    }

    // POST api/Users/me/avatar: doi anh dai dien cua chinh minh.
    // Dung POST vi ApiClient.postMultipart chi ho tro POST (giong Reels).
    // Multipart: image (file, bat buoc), luu uploads/avatars/{uid}/avatar.jpg,
    // ghi de anh cu nen khong can xoa file cu.
    [HttpPost("me/avatar")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    public async Task<IActionResult> UploadAvatar([FromForm] UploadAvatarRequest req)
    {
        if (req.Image == null || req.Image.Length == 0)
            return BadRequest(new { message = "Hãy chọn một ảnh đại diện" });
        var user = await _users.FindByIdAsync(MyId);
        if (user == null) return Unauthorized();

        var folder = Path.Combine(_env.WebRootPath ?? "wwwroot", "uploads", "avatars", MyId);
        Directory.CreateDirectory(folder);
        var extension = Path.GetExtension(req.Image.FileName).ToLowerInvariant();
        if (extension is not (".jpg" or ".jpeg" or ".png" or ".webp" or ".gif"))
            return BadRequest(new { message = "Ảnh cần ở định dạng JPG, PNG, WebP hoặc GIF." });
        var filename = $"{Guid.NewGuid():N}{extension}";
        var path = Path.Combine(folder, filename);
        await using (var stream = System.IO.File.Create(path))
        {
            await req.Image.CopyToAsync(stream);
        }
        user.AvatarUrl = AbsoluteUrl($"uploads/avatars/{MyId}/{filename}");
        await _users.UpdateAsync(user);
        return Ok(ToDto(user));
    }

    // PUT api/Users/me/password: doi mat khau khi dang dang nhap.
    // Can mat khau cu dung, mat khau moi toi thieu 6 ky tu.
    // Tai khoan Google (khong co mat khau) se bao loi ro, khong tu
    // tao mat khau bang API nay.
    [HttpPut("me/password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.NewPassword) || req.NewPassword.Length < 6)
            return BadRequest(new { message = "Mật khẩu mới tối thiểu 6 ký tự" });

        var user = await _users.FindByIdAsync(MyId);
        if (user == null) return Unauthorized();
        if (string.IsNullOrEmpty(user.PasswordHash))
            return BadRequest(new { message = "Tài khoản đăng nhập bằng Google chưa có mật khẩu để đổi" });

        var result = await _users.ChangePasswordAsync(user, req.CurrentPassword, req.NewPassword);
        if (!result.Succeeded)
            return BadRequest(new { message = string.Join("; ", result.Errors.Select(e => e.Description)) });
        return Ok(new { message = "Đã đổi mật khẩu" });
    }

    // PUT api/Users/me/online
    // Giong ChatService.setOnline(): HomeScreen goi khi app resumed/paused.
    [HttpPut("me/online")]
    public async Task<IActionResult> SetOnline([FromBody] SetOnlineRequest req)
    {
        var user = await _users.FindByIdAsync(MyId);
        if (user == null) return Unauthorized();
        user.Online = req.Online;
        user.LastSeen = DateTime.UtcNow;
        await _users.UpdateAsync(user);
        return Ok(ToDto(user));
    }
}
