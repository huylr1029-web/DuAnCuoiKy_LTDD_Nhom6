using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Data;
using MessengerCallApi.Hubs;
using MessengerCallApi.Models;

namespace MessengerCallApi.Controllers;

// Cuoc goi nhom, tach rieng khoi Call 1-1 de khong lam hong luong
// goi 1-1 dang chay.
// - Tao: POST /api/GroupCalls {participantIds, isVideo}
//   Chi goi nhom voi BAN BE (accepted) vi quy tac bao mat: nguoi la
//   khong duoc biet tai khoan, cung khong duoc moi vao cuoc goi nhom.
//   Can it nhat 2 nguoi khac (tong cong it nhat 3 nguoi ke ca nguoi tao).
//   Id la Guid khong dau gach, cung la ten kenh Agora.
// - Moi: backend gui SignalR IncomingGroupCall toi nhom user_{uid}
//   cua tung nguoi duoc moi. Nguoi duoc moi poll GET /api/GroupCalls/incoming
//   de chac chan khong sot neu SignalR mat ket noi.
// - Vao: PUT /api/GroupCalls/{id}/join (invited -> accepted).
// - Roi: PUT /api/GroupCalls/{id}/leave (accepted/invited -> left).
//   Nguoi tao roi khoi thi cuoc goi ket thuc cho tat ca.
// - Ket thuc: PUT /api/GroupCalls/{id}/end (chi nguoi tao).
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class GroupCallsController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;
    private readonly IHubContext<ChatHub> _hub;

    public GroupCallsController(ApplicationDbContext db, UserManager<AppUser> users, IHubContext<ChatHub> hub)
    {
        _db = db;
        _users = users;
        _hub = hub;
    }

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    private static GroupCallDto ToDto(GroupCall c) =>
        new(c.Id, c.CreatorId, c.CreatorName, c.IsVideo, c.Status, c.CreatedAt,
            c.Participants.Select(p => new GroupCallParticipantDto(p.UserId, p.UserName, p.Status)).ToList());

    private async Task<bool> IsFriend(string otherId)
    {
        return await _db.FriendRequests.AnyAsync(r =>
            r.Status == "accepted" &&
            ((r.SenderId == MyId && r.ReceiverId == otherId) ||
             (r.SenderId == otherId && r.ReceiverId == MyId)));
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateGroupCallRequest req)
    {
        var participantIds = (req.ParticipantIds ?? new List<string>()).Distinct().Where(id => id != MyId).ToList();
        if (participantIds.Count < 2)
            return BadRequest(new { message = "Gọi nhóm cần ít nhất 2 bạn (tổng cộng ít nhất 3 người). Chọn 1 người thì dùng gọi 1-1." });

        var me = await _users.FindByIdAsync(MyId);
        if (me == null) return Unauthorized();

        var participants = new List<GroupCallParticipant>
        {
            new() { UserId = MyId, UserName = me.Name, Status = "accepted" },
        };
        foreach (var pid in participantIds)
        {
            var user = await _users.FindByIdAsync(pid);
            if (user == null) return NotFound(new { message = "Không tìm thấy một người được mời" });
            if (!await IsFriend(pid))
                return BadRequest(new { message = $"Chỉ gọi nhóm với bạn bè. {user.Name} chưa phải bạn bè của bạn." });
            participants.Add(new GroupCallParticipant { UserId = pid, UserName = user.Name, Status = "invited" });
        }

        var call = new GroupCall
        {
            Id = Guid.NewGuid().ToString("N"),
            CreatorId = MyId,
            CreatorName = me.Name,
            IsVideo = req.IsVideo,
            Status = "ongoing",
            CreatedAt = DateTime.UtcNow,
            Participants = participants,
        };
        _db.GroupCalls.Add(call);
        await _db.SaveChangesAsync();

        var dto = ToDto(call);
        foreach (var pid in participantIds)
        {
            await _hub.Clients.Group($"user_{pid}").SendAsync("IncomingGroupCall", dto);
        }
        return Ok(dto);
    }

    [HttpGet("incoming")]
    public async Task<IActionResult> Incoming()
    {
        var calls = await _db.GroupCalls
            .Include(c => c.Participants)
            .Where(c => c.Status == "ongoing" &&
                        c.Participants.Any(p => p.UserId == MyId && p.Status == "invited"))
            .OrderByDescending(c => c.CreatedAt)
            .ToListAsync();
        return Ok(calls.Select(ToDto));
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> One(string id)
    {
        var call = await _db.GroupCalls.Include(c => c.Participants).FirstOrDefaultAsync(c => c.Id == id);
        if (call == null) return NotFound(new { message = "Không tìm thấy cuộc gọi nhóm" });
        if (!call.Participants.Any(p => p.UserId == MyId)) return Forbid();
        return Ok(ToDto(call));
    }

    [HttpPut("{id}/join")]
    public async Task<IActionResult> Join(string id)
    {
        var call = await _db.GroupCalls.Include(c => c.Participants).FirstOrDefaultAsync(c => c.Id == id);
        if (call == null) return NotFound(new { message = "Không tìm thấy cuộc gọi nhóm" });
        if (call.Status != "ongoing") return BadRequest(new { message = "Cuộc gọi nhóm đã kết thúc" });
        var participant = call.Participants.FirstOrDefault(p => p.UserId == MyId);
        if (participant == null) return Forbid();
        participant.Status = "accepted";
        await _db.SaveChangesAsync();
        return Ok(ToDto(call));
    }

    [HttpPut("{id}/leave")]
    public async Task<IActionResult> Leave(string id)
    {
        var call = await _db.GroupCalls.Include(c => c.Participants).FirstOrDefaultAsync(c => c.Id == id);
        if (call == null) return NotFound(new { message = "Không tìm thấy cuộc gọi nhóm" });
        var participant = call.Participants.FirstOrDefault(p => p.UserId == MyId);
        if (participant == null) return Forbid();
        if (call.CreatorId == MyId)
        {
            call.Status = "ended";
            foreach (var p in call.Participants)
            {
                await _hub.Clients.Group($"user_{p.UserId}").SendAsync("GroupCallEnded", ToDto(call));
            }
        }
        else
        {
            participant.Status = "left";
        }
        await _db.SaveChangesAsync();
        return Ok(ToDto(call));
    }

    [HttpPut("{id}/end")]
    public async Task<IActionResult> End(string id)
    {
        var call = await _db.GroupCalls.Include(c => c.Participants).FirstOrDefaultAsync(c => c.Id == id);
        if (call == null) return NotFound(new { message = "Không tìm thấy cuộc gọi nhóm" });
        if (call.CreatorId != MyId) return Forbid();
        call.Status = "ended";
        await _db.SaveChangesAsync();
        foreach (var p in call.Participants)
        {
            await _hub.Clients.Group($"user_{p.UserId}").SendAsync("GroupCallEnded", ToDto(call));
        }
        return Ok(ToDto(call));
    }
}
