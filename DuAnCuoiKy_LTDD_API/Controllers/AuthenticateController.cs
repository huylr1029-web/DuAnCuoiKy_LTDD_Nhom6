using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Google.Apis.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using MessengerCallApi.Data;
using MessengerCallApi.Models;

namespace MessengerCallApi.Controllers;

// Giong kieu Tuan 7: AuthenticateController + Identity + JWT Bearer.
// Route giu dang api/Authenticate/... de Flutter doi tu Firebase sang
// chi can doi base URL, khong can doi y nghia tung chuc nang.
[ApiController]
[Route("api/[controller]")]
public class AuthenticateController : ControllerBase
{
    private readonly UserManager<AppUser> _users;
    private readonly ApplicationDbContext _db;
    private readonly IConfiguration _config;

    public AuthenticateController(
        UserManager<AppUser> users, ApplicationDbContext db, IConfiguration config)
    {
        _users = users;
        _db = db;
        _config = config;
    }

    private static UserDto ToDto(AppUser u) =>
        new(u.Id, u.Name, u.Email ?? "", u.PhoneNumber, u.Online, u.LastSeen, u.AvatarUrl);

    private string CreateToken(AppUser user)
    {
        var jwt = _config.GetSection("JWTKey");
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Secret"]!));
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id),
            new Claim(ClaimTypes.Email, user.Email ?? ""),
            new Claim(ClaimTypes.Name, user.Name),
        };
        var token = new JwtSecurityToken(
            issuer: jwt["ValidIssuer"],
            audience: jwt["ValidAudience"],
            claims: claims,
            expires: DateTime.UtcNow.AddDays(7),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private async Task<AppUser?> MeAsync()
    {
        var uid = User.FindFirstValue(ClaimTypes.NameIdentifier);
        return uid == null ? null : await _users.FindByIdAsync(uid);
    }

    // POST api/Authenticate/register
    // Thay cho AuthService.register(): Firebase createUserWithEmailAndPassword
    // + ghi users/{uid}. So dien thoai chuan hoa giong ben Flutter.
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest req)
    {
        var phone = PhoneHelper.Normalize(req.Phone);
        if (phone == null)
            return BadRequest(new { message = "Số điện thoại không hợp lệ" });
        if (string.IsNullOrWhiteSpace(req.Name))
            return BadRequest(new { message = "Vui lòng nhập họ tên" });
        if (await _db.Users.AnyAsync(u => u.PhoneNumber == phone))
            return BadRequest(new { message = "Số điện thoại đã được đăng ký. Hãy dùng số khác." });

        var user = new AppUser
        {
            UserName = req.Email.Trim(),
            Email = req.Email.Trim(),
            PhoneNumber = phone,
            Name = req.Name.Trim(),
            Online = true,
            CreatedAt = DateTime.UtcNow,
            LastSeen = DateTime.UtcNow,
        };
        var result = await _users.CreateAsync(user, req.Password);
        if (!result.Succeeded)
            return BadRequest(new { message = string.Join("; ", result.Errors.Select(e => e.Description)) });

        return Ok(new AuthResponse(CreateToken(user), ToDto(user)));
    }

    // POST api/Authenticate/login
    // Thay cho AuthService.login(): signInWithEmailAndPassword + ensureUserProfile.
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest req)
    {
        var user = await _users.FindByEmailAsync(req.Email.Trim());
        if (user == null || !await _users.CheckPasswordAsync(user, req.Password))
            return Unauthorized(new { message = "Sai email hoặc mật khẩu" });

        user.Online = true;
        user.LastSeen = DateTime.UtcNow;
        await _users.UpdateAsync(user);
        return Ok(new AuthResponse(CreateToken(user), ToDto(user)));
    }

    // POST api/Authenticate/google
    // Thay cho AuthService.signInWithGoogle(): Flutter lay idToken bang
    // google_sign_in roi gui len day, backend xac thuc idToken voi Google.
    // Can cau hinh Google:ClientId trong appsettings.json.
    // Neu chua cau hinh thi bao ro, khong tu tao user ao.
    [HttpPost("google")]
    public async Task<IActionResult> Google([FromBody] GoogleLoginRequest req)
    {
        var clientId = _config["Google:ClientId"];
        if (string.IsNullOrWhiteSpace(clientId))
            return BadRequest(new { message = "Backend chưa cấu hình Google:ClientId" });

        if (string.IsNullOrWhiteSpace(req.IdToken))
            return BadRequest(new { message = "Ứng dụng chưa lấy được Google ID token. Kiểm tra OAuth Android SHA-1 và Web Client ID." });

        GoogleJsonWebSignature.Payload payload;
        try
        {
            payload = await GoogleJsonWebSignature.ValidateAsync(req.IdToken,
                new GoogleJsonWebSignature.ValidationSettings { Audience = new[] { clientId } });
        }
        catch (InvalidJwtException)
        {
            return Unauthorized(new { message = "Google ID token không hợp lệ hoặc Web Client ID không khớp Google:ClientId." });
        }

        var user = await _users.FindByEmailAsync(payload.Email);
        if (user == null)
        {
            user = new AppUser
            {
                UserName = payload.Email,
                Email = payload.Email,
                Name = payload.Name ?? payload.Email.Split('@')[0],
                Online = true,
                CreatedAt = DateTime.UtcNow,
                LastSeen = DateTime.UtcNow,
            };
            // Tai khoan Google khong co mat khau; tao user khong mat khau.
            var created = await _users.CreateAsync(user);
            if (!created.Succeeded)
                return BadRequest(new { message = string.Join("; ", created.Errors.Select(e => e.Description)) });
        }
        else
        {
            user.Online = true;
            user.LastSeen = DateTime.UtcNow;
            if (string.IsNullOrWhiteSpace(user.Name) && !string.IsNullOrWhiteSpace(payload.Name))
                user.Name = payload.Name;
            await _users.UpdateAsync(user);
        }
        return Ok(new AuthResponse(CreateToken(user), ToDto(user)));
    }

    // GET api/Authenticate/me
    // Thay cho ensureUserProfile() + authStateChanges: app mo len goi API
    // nay de dong bo ho so va biet minh dang dang nhap.
    [Authorize]
    [HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var user = await MeAsync();
        if (user == null) return Unauthorized();
        user.Online = true;
        user.LastSeen = DateTime.UtcNow;
        await _users.UpdateAsync(user);
        return Ok(ToDto(user));
    }

    // POST api/Authenticate/logout
    // Thay cho AuthService.logout(): danh dau offline roi Flutter xoa token.
    // JWT la stateless nen server khong co danh sach token de thu hoi.
    [Authorize]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        var user = await MeAsync();
        if (user != null)
        {
            user.Online = false;
            user.LastSeen = DateTime.UtcNow;
            await _users.UpdateAsync(user);
        }
        return Ok(new { message = "Đã đăng xuất" });
    }

    // POST api/Authenticate/forgot-password
    // Thay cho sendPasswordResetEmail(). Luu y trung thuc: backend nay
    // CHUA gui email that (chua cau hinh SMTP). O Development, endpoint
    // tra them resetToken de demo doi mat khau; o Production chi tra
    // thong bao chung de khong lo email co ton tai hay khong.
    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest req)
    {
        var user = await _users.FindByEmailAsync(req.Email.Trim());
        if (user == null)
            return Ok(new { message = "Nếu email đã đăng ký, bạn sẽ nhận được liên kết đặt lại mật khẩu." });

        var token = await _users.GeneratePasswordResetTokenAsync(user);
        if (HttpContext.RequestServices.GetService<IWebHostEnvironment>()?.IsDevelopment() == true)
            return Ok(new
            {
                message = "Chưa cấu hình SMTP nên email chưa được gửi thật. Dùng resetToken dưới đây để demo đổi mật khẩu.",
                resetToken = token,
            });
        // TODO (neu muon gui email that): cau hinh SMTP roi gui token nay
        // qua email cho user, khong tra token ra response o Production.
        return Ok(new { message = "Nếu email đã đăng ký, bạn sẽ nhận được liên kết đặt lại mật khẩu." });
    }

    // POST api/Authenticate/reset-password
    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest req)
    {
        var user = await _users.FindByEmailAsync(req.Email.Trim());
        if (user == null) return BadRequest(new { message = "Email hoặc token không hợp lệ" });
        var result = await _users.ResetPasswordAsync(user, req.Token, req.NewPassword);
        if (!result.Succeeded)
            return BadRequest(new { message = string.Join("; ", result.Errors.Select(e => e.Description)) });
        return Ok(new { message = "Đã đổi mật khẩu" });
    }
}
