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

// Chat nhom, tach rieng khoi Chat 1-1 de khong lam hong luong 1-1.
// - Tao: POST /api/GroupChats {name, memberIds}
//   Can ten nhom + it nhat 2 thanh vien khac (tong cong it nhat 3 nguoi),
//   thanh vien phai la BAN BE (accepted) theo quy tac bao mat.
// - Danh sach: GET /api/GroupChats/my
// - Tin nhan: GET /api/GroupChats/{id}/messages, POST .../messages
//   (text / location, Text="lat,lng" khi type=location),
//   POST .../image (multipart, anh luu uploads/groupchat/{id}/).
// - Chi thanh vien moi doc / gui. Tin moi day qua SignalR toi nhom
//   user_{uid} cua tung thanh vien voi su kien NewGroupMessage,
//   dong thoi Flutter poll 3 giay de chac chan khong sot.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class GroupChatsController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;
    private readonly IHubContext<ChatHub> _hub;
    private readonly IWebHostEnvironment _env;

    public GroupChatsController(ApplicationDbContext db, UserManager<AppUser> users, IHubContext<ChatHub> hub, IWebHostEnvironment env)
    {
        _db = db;
        _users = users;
        _hub = hub;
        _env = env;
    }

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    private string AbsoluteUrl(string relativePath) =>
        $"{Request.Scheme}://{Request.Host}/{relativePath.Replace('\\', '/')}";

    private static GroupChatDto ToDto(GroupChat c) =>
        new(c.Id, c.Name, c.CreatorId, c.LastMessage, c.LastSenderId, c.UpdatedAt,
            c.Members.Select(m => new GroupChatMemberDto(m.UserId, m.UserName)).ToList());

    private static GroupChatMessageDto ToMessageDto(GroupChatMessage m) =>
        new(m.Id, m.GroupChatId, m.SenderId, m.SenderName, m.Text, m.Type, m.CreatedAt);

    private async Task<bool> IsFriend(string otherId)
    {
        return await _db.FriendRequests.AnyAsync(r =>
            r.Status == "accepted" &&
            ((r.SenderId == MyId && r.ReceiverId == otherId) ||
             (r.SenderId == otherId && r.ReceiverId == MyId)));
    }

    private async Task<GroupChat?> MyGroupChat(string id)
    {
        var chat = await _db.GroupChats.Include(c => c.Members).FirstOrDefaultAsync(c => c.Id == id);
        if (chat == null) return null;
        if (!chat.Members.Any(m => m.UserId == MyId)) return null;
        return chat;
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateGroupChatRequest req)
    {
        var name = (req.Name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name) || name.Length > 100)
            return BadRequest(new { message = "Tên nhóm không được để trống và tối đa 100 ký tự" });
        var memberIds = (req.MemberIds ?? new List<string>()).Distinct().Where(id => id != MyId).ToList();
        if (memberIds.Count < 2)
            return BadRequest(new { message = "Nhóm chat cần ít nhất 2 bạn (tổng cộng ít nhất 3 người)." });

        var me = await _users.FindByIdAsync(MyId);
        if (me == null) return Unauthorized();

        var members = new List<GroupChatMember>
        {
            new() { UserId = MyId, UserName = me.Name },
        };
        foreach (var pid in memberIds)
        {
            var user = await _users.FindByIdAsync(pid);
            if (user == null) return NotFound(new { message = "Không tìm thấy một thành viên" });
            if (!await IsFriend(pid))
                return BadRequest(new { message = $"Chỉ thêm bạn bè vào nhóm. {user.Name} chưa phải bạn bè của bạn." });
            members.Add(new GroupChatMember { UserId = pid, UserName = user.Name });
        }

        var chat = new GroupChat
        {
            Id = Guid.NewGuid().ToString("N"),
            Name = name,
            CreatorId = MyId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            Members = members,
        };
        _db.GroupChats.Add(chat);
        await _db.SaveChangesAsync();
        return Ok(ToDto(chat));
    }

    [HttpGet("my")]
    public async Task<IActionResult> Mine()
    {
        var chats = await _db.GroupChats
            .Include(c => c.Members)
            .Where(c => c.Members.Any(m => m.UserId == MyId))
            .OrderByDescending(c => c.UpdatedAt)
            .ToListAsync();
        return Ok(chats.Select(ToDto));
    }

    [HttpGet("{id}/messages")]
    public async Task<IActionResult> Messages(string id, [FromQuery] int take = 200)
    {
        var chat = await MyGroupChat(id);
        if (chat == null) return NotFound(new { message = "Không tìm thấy nhóm chat hoặc bạn không phải thành viên" });
        var list = await _db.GroupChatMessages
            .Where(m => m.GroupChatId == id)
            .OrderByDescending(m => m.CreatedAt)
            .ThenByDescending(m => m.Id)
            .Take(take)
            .ToListAsync();
        return Ok(list.Select(ToMessageDto));
    }

    private async Task<GroupChatMessageDto> AddMessageAsync(GroupChat chat, string text, string type)
    {
        var me = await _users.FindByIdAsync(MyId);
        var message = new GroupChatMessage
        {
            GroupChatId = chat.Id,
            SenderId = MyId,
            SenderName = me?.Name ?? "",
            Text = text,
            Type = type,
            CreatedAt = DateTime.UtcNow,
        };
        _db.GroupChatMessages.Add(message);
        chat.LastMessage = type switch
        {
            "image" => "📷 Đã gửi hình ảnh",
            "location" => "📍 Đã gửi vị trí",
            _ => text,
        };
        chat.LastSenderId = MyId;
        chat.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var dto = ToMessageDto(message);
        foreach (var member in chat.Members.Where(m => m.UserId != MyId))
        {
            await _hub.Clients.Group($"user_{member.UserId}").SendAsync("NewGroupMessage", dto);
        }
        return dto;
    }

    [HttpPost("{id}/messages")]
    public async Task<IActionResult> Send(string id, [FromBody] SendGroupChatMessageRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Text))
            return BadRequest(new { message = "Tin nhắn trống" });
        var chat = await MyGroupChat(id);
        if (chat == null) return NotFound(new { message = "Không tìm thấy nhóm chat hoặc bạn không phải thành viên" });
        var dto = await AddMessageAsync(chat, req.Text.Trim(), req.Type);
        return Ok(dto);
    }

    [HttpPost("{id}/image")]
    [RequestSizeLimit(50 * 1024 * 1024)]
    public async Task<IActionResult> SendImage(string id, [FromForm] CreateGroupChatImageRequest req)
    {
        if (req.Image == null || req.Image.Length == 0)
            return BadRequest(new { message = "Hãy chọn một ảnh" });
        var chat = await MyGroupChat(id);
        if (chat == null) return NotFound(new { message = "Không tìm thấy nhóm chat hoặc bạn không phải thành viên" });

        var folder = Path.Combine(_env.WebRootPath ?? "wwwroot", "uploads", "groupchat", id);
        Directory.CreateDirectory(folder);
        var ext = Path.GetExtension(req.Image.FileName);
        if (string.IsNullOrWhiteSpace(ext)) ext = ".jpg";
        var fileName = $"{Guid.NewGuid()}{ext}";
        var path = Path.Combine(folder, fileName);
        await using (var stream = System.IO.File.Create(path))
        {
            await req.Image.CopyToAsync(stream);
        }
        var url = AbsoluteUrl($"uploads/groupchat/{id}/{fileName}");
        var dto = await AddMessageAsync(chat, url, "image");
        return Ok(dto);
    }
}
