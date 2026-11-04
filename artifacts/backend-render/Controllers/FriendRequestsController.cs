using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Data;
using MessengerCallApi.Models;

namespace MessengerCallApi.Controllers;

// Thay cho collection friend_requests ben Flutter.
// Logic giu nguyen ban goc:
// - Neu nguoi kia da gui loi moi dang pending thi bao "hay chap nhan ben duoi".
// - Neu da ton tai thi bao "da gui truoc do" hoac "da la ban be".
// - Chi nguoi nhan moi duoc chap nhan / tu choi, chi khi dang pending.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class FriendRequestsController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;

    public FriendRequestsController(ApplicationDbContext db, UserManager<AppUser> users)
    {
        _db = db;
        _users = users;
    }

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    private static FriendRequestDto ToDto(FriendRequest f) =>
        new(f.Id, f.SenderId, f.ReceiverId, f.SenderName, f.ReceiverName,
            f.Status, f.CreatedAt, f.RespondedAt);

    // POST api/FriendRequests
    [HttpPost]
    public async Task<IActionResult> Invite([FromBody] InviteRequest req)
    {
        if (req.ReceiverId == MyId)
            return BadRequest(new { message = "Không thể kết bạn với chính mình" });

        var me = await _users.FindByIdAsync(MyId);
        var target = await _users.FindByIdAsync(req.ReceiverId);
        if (me == null || target == null)
            return NotFound(new { message = "Không tìm thấy tài khoản" });

        // Co loi moi nguoc dang pending -> bao chap nhan ben duoi.
        var reverse = await _db.FriendRequests.FirstOrDefaultAsync(f =>
            f.SenderId == req.ReceiverId && f.ReceiverId == MyId && f.Status == "pending");
        if (reverse != null)
            return Conflict(new { message = "Người này đã gửi lời mời cho bạn. Hãy chấp nhận bên dưới." });

        var current = await _db.FriendRequests.FirstOrDefaultAsync(f =>
            f.SenderId == MyId && f.ReceiverId == req.ReceiverId);
        if (current != null)
            return Conflict(new
            {
                message = current.Status == "accepted" ? "Hai bạn đã là bạn bè." : "Đã gửi lời mời trước đó.",
                request = ToDto(current),
            });

        var created = new FriendRequest
        {
            SenderId = MyId,
            ReceiverId = req.ReceiverId,
            SenderName = me.Name,
            ReceiverName = target.Name,
            Status = "pending",
            CreatedAt = DateTime.UtcNow,
        };
        _db.FriendRequests.Add(created);
        await _db.SaveChangesAsync();
        return Ok(ToDto(created));
    }

    // GET api/FriendRequests?direction=incoming|outgoing&status=pending|accepted
    // - incoming + pending: loi moi dang cho (FriendsScreen phan tren).
    // - outgoing + accepted va incoming + accepted: danh sach ban be.
    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] string direction = "incoming",
        [FromQuery] string status = "pending")
    {
        var query = _db.FriendRequests.AsQueryable();
        query = direction == "outgoing"
            ? query.Where(f => f.SenderId == MyId)
            : query.Where(f => f.ReceiverId == MyId);
        if (status is "pending" or "accepted" or "rejected")
            query = query.Where(f => f.Status == status);

        var list = await query.OrderByDescending(f => f.CreatedAt).ToListAsync();
        return Ok(list.Select(ToDto));
    }

    // PUT api/FriendRequests/{id}/respond
    [HttpPut("{id}/respond")]
    public async Task<IActionResult> Respond(int id, [FromBody] RespondRequest req)
    {
        if (req.Status is not ("accepted" or "rejected"))
            return BadRequest(new { message = "Trạng thái phải là accepted hoặc rejected" });

        var item = await _db.FriendRequests.FindAsync(id);
        if (item == null) return NotFound(new { message = "Không tìm thấy lời mời" });
        if (item.ReceiverId != MyId)
            return Forbid();
        if (item.Status != "pending")
            return Conflict(new { message = "Lời mời này đã được xử lý" });

        item.Status = req.Status;
        item.RespondedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(ToDto(item));
    }

    // DELETE api/FriendRequests/{id}: huy ket ban (hoac huy loi moi).
    // Chi 1 trong 2 ben moi duoc xoa. Xoa xong thi 2 ben co the gui
    // lai loi moi tu dau. Biet danh 2 chieu giua 2 nguoi cung bi xoa.
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        var item = await _db.FriendRequests.FindAsync(id);
        if (item == null) return NotFound(new { message = "Không tìm thấy bạn bè" });
        if (item.SenderId != MyId && item.ReceiverId != MyId)
            return Forbid();

        var otherId = item.SenderId == MyId ? item.ReceiverId : item.SenderId;
        var nicknames = await _db.FriendNicknames
            .Where(n => (n.OwnerId == MyId && n.PeerId == otherId) ||
                        (n.OwnerId == otherId && n.PeerId == MyId))
            .ToListAsync();
        _db.FriendNicknames.RemoveRange(nicknames);
        _db.FriendRequests.Remove(item);
        await _db.SaveChangesAsync();
        return Ok(new { message = "Đã xóa bạn bè" });
    }
}
