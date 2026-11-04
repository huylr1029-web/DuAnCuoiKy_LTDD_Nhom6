using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Data;
using MessengerCallApi.Models;

namespace MessengerCallApi.Controllers;

// Biet danh rieng cho ban be: chi nguoi dat moi thay.
// - GET api/FriendNicknames: tat ca biet danh minh da dat.
// - PUT api/FriendNicknames/{peerId}: dat / doi biet danh cho 1 ban.
// - DELETE api/FriendNicknames/{peerId}: xoa biet danh, tro ve ten that.
// Biet danh khong doi ten that cua ban do o tai khoan cua ho.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class FriendNicknamesController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;

    public FriendNicknamesController(ApplicationDbContext db, UserManager<AppUser> users)
    {
        _db = db;
        _users = users;
    }

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var list = await _db.FriendNicknames
            .Where(n => n.OwnerId == MyId)
            .OrderBy(n => n.Nickname)
            .ToListAsync();
        return Ok(list.Select(n => new FriendNicknameDto(n.PeerId, n.Nickname)));
    }

    [HttpPut("{peerId}")]
    public async Task<IActionResult> Set(string peerId, [FromBody] SetNicknameRequest req)
    {
        var nickname = req.Nickname?.Trim() ?? "";
        if (peerId == MyId)
            return BadRequest(new { message = "Không đặt biệt danh cho chính mình ở đây, dùng đổi tên của mình" });
        if (string.IsNullOrWhiteSpace(nickname) || nickname.Length > 100)
            return BadRequest(new { message = "Biệt danh không được để trống và tối đa 100 ký tự" });

        var peer = await _users.FindByIdAsync(peerId);
        if (peer == null) return NotFound(new { message = "Không tìm thấy người dùng" });

        var existing = await _db.FriendNicknames
            .FirstOrDefaultAsync(n => n.OwnerId == MyId && n.PeerId == peerId);
        if (existing == null)
        {
            existing = new FriendNickname
            {
                OwnerId = MyId,
                PeerId = peerId,
                Nickname = nickname,
                UpdatedAt = DateTime.UtcNow,
            };
            _db.FriendNicknames.Add(existing);
        }
        else
        {
            existing.Nickname = nickname;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        await _db.SaveChangesAsync();
        return Ok(new FriendNicknameDto(peerId, nickname));
    }

    [HttpDelete("{peerId}")]
    public async Task<IActionResult> Delete(string peerId)
    {
        var existing = await _db.FriendNicknames
            .FirstOrDefaultAsync(n => n.OwnerId == MyId && n.PeerId == peerId);
        if (existing == null) return NotFound(new { message = "Chưa đặt biệt danh cho người này" });
        _db.FriendNicknames.Remove(existing);
        await _db.SaveChangesAsync();
        return Ok(new { message = "Đã xóa biệt danh" });
    }
}
