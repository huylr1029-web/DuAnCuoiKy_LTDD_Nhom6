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

// Thay cho CallService: startCall(), incomingCalls(), callStream(),
// updateStatus(). Day la bao hieu (signaling) qua REST + SignalR,
// KHONG thay Agora: am thanh / hinh anh van chay qua Agora,
// channelId cua Agora chinh la Id cua Call nay.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class CallsController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;
    private readonly IHubContext<ChatHub> _hub;

    public CallsController(ApplicationDbContext db, UserManager<AppUser> users, IHubContext<ChatHub> hub)
    {
        _db = db;
        _users = users;
        _hub = hub;
    }

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    // POST api/Calls
    // Giong startCall(): tao calls/{callId} status ringing, tra ve callId.
    [HttpPost]
    public async Task<IActionResult> Start([FromBody] StartCallRequest req)
    {
        if (req.PeerId == MyId)
            return BadRequest(new { message = "Hãy chọn tài khoản khác để gọi." });
        var me = await _users.FindByIdAsync(MyId);
        var peer = await _users.FindByIdAsync(req.PeerId);
        if (me == null || peer == null)
            return NotFound(new { message = "Không tìm thấy người nhận cuộc gọi" });

        var call = new Call
        {
            CallerId = MyId,
            CallerName = me.Name,
            CalleeId = req.PeerId,
            CalleeName = peer.Name,
            IsVideo = req.IsVideo,
            Status = "ringing",
            CreatedAt = DateTime.UtcNow,
        };
        _db.Calls.Add(call);
        await _db.SaveChangesAsync();

        // Day realtime cho nguoi nhan (thay cho snapshots() ben Flutter).
        await _hub.Clients.Group($"user_{req.PeerId}").SendAsync("IncomingCall", call);
        return Ok(call);
    }

    // GET api/Calls/incoming
    // Giong incomingCalls(): chi cuoc goi dang ringing toi minh.
    // Cuoc ringing qua 40 giay (ban goc bo qua cuoc cu > 40s) duoc
    // tu dong chuyen sang missed o day de khong do chuong mai.
    [HttpGet("incoming")]
    public async Task<IActionResult> Incoming()
    {
        var cutoff = DateTime.UtcNow.AddSeconds(-40);
        var stale = await _db.Calls
            .Where(c => c.CalleeId == MyId && c.Status == "ringing" && c.CreatedAt < cutoff)
            .ToListAsync();
        foreach (var c in stale)
        {
            c.Status = "missed";
            c.UpdatedAt = DateTime.UtcNow;
        }
        if (stale.Count > 0) await _db.SaveChangesAsync();

        var list = await _db.Calls
            .Where(c => c.CalleeId == MyId && c.Status == "ringing")
            .OrderByDescending(c => c.CreatedAt)
            .ToListAsync();
        return Ok(list);
    }

    // GET api/Calls/{id}
    // Giong callStream(id) o dang REST: Flutter hoi lai khi can, hoac
    // nhan CallStatusChanged qua SignalR thay vi snapshots().
    [HttpGet("{id}")]
    public async Task<IActionResult> One(string id)
    {
        var call = await _db.Calls.FindAsync(id);
        if (call == null) return NotFound(new { message = "Không tìm thấy cuộc gọi" });
        if (call.CallerId != MyId && call.CalleeId != MyId) return Forbid();
        return Ok(call);
    }

    // GET api/Calls/my?direction=outgoing|incoming|all
    // Dung cho CallsTab va ProfileTab "Hoat dong cuoc goi gan day".
    [HttpGet("my")]
    public async Task<IActionResult> Mine([FromQuery] string direction = "all")
    {
        var query = _db.Calls.AsQueryable();
        query = direction switch
        {
            "outgoing" => query.Where(c => c.CallerId == MyId),
            "incoming" => query.Where(c => c.CalleeId == MyId),
            _ => query.Where(c => c.CallerId == MyId || c.CalleeId == MyId),
        };
        var list = await query.OrderByDescending(c => c.CreatedAt).ToListAsync();
        return Ok(list);
    }

    // PUT api/Calls/{id}/status
    // Giong updateStatus(): accepted | rejected | ended | missed.
    // Chi nguoi goi hoac nguoi nhan moi duoc doi trang thai.
    [HttpPut("{id}/status")]
    public async Task<IActionResult> UpdateStatus(string id, [FromBody] UpdateCallStatusRequest req)
    {
        if (req.Status is not ("accepted" or "rejected" or "ended" or "missed"))
            return BadRequest(new { message = "Trạng thái không hợp lệ" });

        var call = await _db.Calls.FindAsync(id);
        if (call == null) return NotFound(new { message = "Không tìm thấy cuộc gọi" });
        if (call.CallerId != MyId && call.CalleeId != MyId) return Forbid();

        if (call.Status == req.Status) return Ok(call);
        if (call.Status is "ended" or "rejected" or "missed")
            return Conflict(new { message = "Cuộc gọi đã kết thúc.", status = call.Status });
        if (req.Status is "accepted" or "rejected")
        {
            if (call.CalleeId != MyId) return Forbid();
            if (call.Status != "ringing")
                return Conflict(new { message = "Cuộc gọi không còn đổ chuông." });
        }
        if (req.Status == "missed" && (call.CallerId != MyId || call.Status != "ringing"))
            return Conflict(new { message = "Không thể đánh dấu nhỡ cho cuộc gọi này." });

        call.Status = req.Status;
        call.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        await _hub.Clients.Group($"user_{call.CallerId}").SendAsync("CallStatusChanged", call);
        await _hub.Clients.Group($"user_{call.CalleeId}").SendAsync("CallStatusChanged", call);
        return Ok(call);
    }
}
