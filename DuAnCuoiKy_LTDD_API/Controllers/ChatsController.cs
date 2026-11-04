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

// Thay cho ChatService: myChats(), messages(), sendMessage(), sendCallLog().
// Tin nhan moi duoc day qua SignalR toi nhom chat_{chatId} va user_{peerId}
// de ben nhan khong can hoi lai server lien tuc (thay cho snapshots()).
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ChatsController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;
    private readonly IHubContext<ChatHub> _hub;
    private readonly IWebHostEnvironment _env;

    public ChatsController(ApplicationDbContext db, UserManager<AppUser> users, IHubContext<ChatHub> hub, IWebHostEnvironment env)
    {
        _db = db;
        _users = users;
        _hub = hub;
        _env = env;
    }

    private string AbsoluteUrl(string relativePath) =>
        $"{Request.Scheme}://{Request.Host}/{relativePath.Replace('\\', '/')}";

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    private static MessageDto ToMessageDto(ChatMessage m) =>
        new(m.Id, m.ChatId, m.SenderId, m.Text, m.Type, m.IsVideo, m.CreatedAt, m.IsRead);

    private async Task<Chat> GetOrCreateChatAsync(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var chat = await _db.Chats.FindAsync(chatId);
        if (chat != null) return chat;

        var me = await _users.FindByIdAsync(MyId);
        var peer = await _users.FindByIdAsync(peerId);
        if (me == null || peer == null)
            throw new InvalidOperationException("Không tìm thấy người dùng");

        // MemberA / MemberB luon theo thu tu sap xep de chatId nhat quan.
        var aFirst = string.CompareOrdinal(MyId, peerId) < 0;
        chat = new Chat
        {
            Id = chatId,
            MemberA = aFirst ? MyId : peerId,
            MemberB = aFirst ? peerId : MyId,
            NameA = aFirst ? me.Name : peer.Name,
            NameB = aFirst ? peer.Name : me.Name,
            UpdatedAt = DateTime.UtcNow,
        };
        _db.Chats.Add(chat);
        await _db.SaveChangesAsync();
        return chat;
    }

    private async Task<MessageDto> AddMessageAsync(string peerId, string text, string type, bool isVideo)
    {
        var chat = await GetOrCreateChatAsync(peerId);
        var message = new ChatMessage
        {
            ChatId = chat.Id,
            SenderId = MyId,
            Text = text,
            Type = type,
            IsVideo = isVideo,
            CreatedAt = DateTime.UtcNow,
        };
        _db.ChatMessages.Add(message);

        // Tin moi ve thi doan chat phai hien lai cho ca 2 ben,
        // neu khong tin moi se bi giau trong muc luu tru.
        var archives = _db.ChatArchives.Where(a => a.ChatId == chat.Id);
        _db.ChatArchives.RemoveRange(archives);

        chat.LastMessage = type switch
        {
            "call" => $"📞 {text}",
            "image" => "📷 Đã gửi hình ảnh",
            "location" => "📍 Đã gửi vị trí",
            "voice" => "🎤 Đã gửi tin nhắn thoại",
            _ => text,
        };
        chat.LastSenderId = MyId;
        chat.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var dto = ToMessageDto(message);
        await _hub.Clients.Group($"chat_{chat.Id}").SendAsync("NewMessage", dto);
        await _hub.Clients.Group($"user_{peerId}").SendAsync("NewMessage", dto);
        return dto;
    }

    // GET api/Chats/my
    // Giong myChats(): chat cua minh, moi nhat len dau.
    [HttpGet("my")]
    public async Task<IActionResult> MyChats()
    {
        var chats = await _db.Chats
            .Where(c => c.MemberA == MyId || c.MemberB == MyId)
            .OrderByDescending(c => c.UpdatedAt)
            .ToListAsync();

        var peerIds = chats.Select(c => c.MemberA == MyId ? c.MemberB : c.MemberA).Distinct().ToList();
        var peers = await _users.Users.Where(u => peerIds.Contains(u.Id)).ToListAsync();
        var archivedIds = await _db.ChatArchives
            .Where(a => a.OwnerId == MyId)
            .Select(a => a.ChatId)
            .ToListAsync();
        var result = chats.Select(c =>
        {
            var peerId = c.MemberA == MyId ? c.MemberB : c.MemberA;
            var peer = peers.FirstOrDefault(u => u.Id == peerId);
            var peerName = c.MemberA == MyId ? c.NameB : c.NameA;
            return new ChatDto(c.Id, peerId, peer?.Name ?? peerName, peer?.Online ?? false,
                c.LastMessage, c.LastSenderId, c.UpdatedAt, archivedIds.Contains(c.Id), peer?.AvatarUrl ?? "");
        });
        return Ok(result);
    }

    // PUT api/Chats/{peerId}/archive: luu tru / giau doan chat, chi minh.
    [HttpPut("{peerId}/archive")]
    public async Task<IActionResult> Archive(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var chat = await _db.Chats.FindAsync(chatId);
        if (chat == null) return NotFound(new { message = "Chưa có đoạn chat với người này" });
        if (!await _db.ChatArchives.AnyAsync(a => a.OwnerId == MyId && a.ChatId == chatId))
        {
            _db.ChatArchives.Add(new ChatArchive { OwnerId = MyId, ChatId = chatId, ArchivedAt = DateTime.UtcNow });
            await _db.SaveChangesAsync();
        }
        return Ok(new { message = "Đã lưu trữ đoạn chat" });
    }

    // DELETE api/Chats/{peerId}/archive: khoi phuc doan chat da luu tru.
    [HttpDelete("{peerId}/archive")]
    public async Task<IActionResult> Unarchive(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var existing = await _db.ChatArchives.FirstOrDefaultAsync(a => a.OwnerId == MyId && a.ChatId == chatId);
        if (existing == null) return NotFound(new { message = "Đoạn chat này không bị lưu trữ" });
        _db.ChatArchives.Remove(existing);
        await _db.SaveChangesAsync();
        return Ok(new { message = "Đã khôi phục đoạn chat" });
    }

    // GET api/Chats/{peerId}/messages?take=200
    // Giong messages(chatId): moi nhat truoc, giong orderBy descending
    // ben Flutter (ListView reverse:true hien tin moi o duoi).
    [HttpGet("{peerId}/messages")]
    public async Task<IActionResult> Messages(string peerId, [FromQuery] int take = 200)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var list = await _db.ChatMessages
            .Where(m => m.ChatId == chatId)
            .OrderByDescending(m => m.CreatedAt)
            .ThenByDescending(m => m.Id)
            .Take(take)
            .ToListAsync();
        return Ok(list.Select(ToMessageDto));
    }

    // POST api/Chats/{peerId}/messages
    [HttpPost("{peerId}/messages")]
    public async Task<IActionResult> Send(string peerId, [FromBody] SendMessageRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Text))
            return BadRequest(new { message = "Tin nhắn trống" });
        if (await _users.FindByIdAsync(peerId) == null)
            return NotFound(new { message = "Không tìm thấy người nhận" });
        var dto = await AddMessageAsync(peerId, req.Text.Trim(), req.Type, req.IsVideo);
        return Ok(dto);
    }

    // POST api/Chats/{peerId}/image: gui hinh anh trong chat.
    // Multipart: image (file, bat buoc). Anh luu wwwroot/uploads/chat/
    // va tin nhan type=image, Text = URL tuyet doi cua anh.
    [HttpPost("{peerId}/image")]
    [RequestSizeLimit(50 * 1024 * 1024)]
    public async Task<IActionResult> SendImage(string peerId, [FromForm] CreateChatImageRequest req)
    {
        if (req.Image == null || req.Image.Length == 0)
            return BadRequest(new { message = "Hãy chọn một ảnh" });
        if (await _users.FindByIdAsync(peerId) == null)
            return NotFound(new { message = "Không tìm thấy người nhận" });

        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var folder = Path.Combine(_env.WebRootPath ?? "wwwroot", "uploads", "chat", chatId);
        Directory.CreateDirectory(folder);
        var ext = Path.GetExtension(req.Image.FileName);
        if (string.IsNullOrWhiteSpace(ext)) ext = ".jpg";
        var fileName = $"{Guid.NewGuid()}{ext}";
        var path = Path.Combine(folder, fileName);
        await using (var stream = System.IO.File.Create(path))
        {
            await req.Image.CopyToAsync(stream);
        }
        var url = AbsoluteUrl($"uploads/chat/{chatId}/{fileName}");
        var dto = await AddMessageAsync(peerId, url, "image", false);
        return Ok(dto);
    }

    // POST api/Chats/{peerId}/voice: gui tin nhan thoai.
    // Multipart: audio (file, bat buoc, .m4a tu Flutter).
    // Luu wwwroot/uploads/chat/{chatId}/, tin nhan type=voice.
    [HttpPost("{peerId}/voice")]
    [RequestSizeLimit(50 * 1024 * 1024)]
    public async Task<IActionResult> SendVoice(string peerId, [FromForm] CreateChatVoiceRequest req)
    {
        if (req.Audio == null || req.Audio.Length == 0)
            return BadRequest(new { message = "Hãy ghi âm trước khi gửi" });
        if (await _users.FindByIdAsync(peerId) == null)
            return NotFound(new { message = "Không tìm thấy người nhận" });

        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var folder = Path.Combine(_env.WebRootPath ?? "wwwroot", "uploads", "chat", chatId);
        Directory.CreateDirectory(folder);
        var ext = Path.GetExtension(req.Audio.FileName);
        if (string.IsNullOrWhiteSpace(ext)) ext = ".m4a";
        var fileName = $"{Guid.NewGuid()}{ext}";
        var path = Path.Combine(folder, fileName);
        await using (var stream = System.IO.File.Create(path))
        {
            await req.Audio.CopyToAsync(stream);
        }
        var url = AbsoluteUrl($"uploads/chat/{chatId}/{fileName}");
        var dto = await AddMessageAsync(peerId, url, "voice", false);
        return Ok(dto);
    }

    // Cam xuc cho tin nhan: moi nguoi toi da 1 cam xuc / tin nhan.
    // GET api/Chats/{peerId}/reactions: tat ca cam xuc trong doan chat.
    [HttpGet("{peerId}/reactions")]
    public async Task<IActionResult> Reactions(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var messageIds = await _db.ChatMessages
            .Where(m => m.ChatId == chatId)
            .Select(m => m.Id)
            .ToListAsync();
        var list = await _db.MessageReactions
            .Where(r => messageIds.Contains(r.MessageId))
            .ToListAsync();
        return Ok(list.Select(r => new MessageReactionDto(r.MessageId, r.UserId, r.Emoji)));
    }

    // PUT api/Chats/messages/{messageId}/reactions: dat / doi cam xuc.
    [HttpPut("messages/{messageId}/reactions")]
    public async Task<IActionResult> SetReaction(int messageId, [FromBody] SetReactionRequest req)
    {
        var allowed = new[] { "👍", "❤️", "😂", "😮", "😢", "😡", "🔥" };
        if (!allowed.Contains(req.Emoji))
            return BadRequest(new { message = "Biểu tượng cảm xúc không hỗ trợ" });
        var message = await _db.ChatMessages.FindAsync(messageId);
        if (message == null) return NotFound(new { message = "Không tìm thấy tin nhắn" });
        var chat = await _db.Chats.FindAsync(message.ChatId);
        if (chat == null || (chat.MemberA != MyId && chat.MemberB != MyId)) return Forbid();

        var existing = await _db.MessageReactions
            .FirstOrDefaultAsync(r => r.MessageId == messageId && r.UserId == MyId);
        if (existing == null)
        {
            existing = new MessageReaction { MessageId = messageId, UserId = MyId, Emoji = req.Emoji, CreatedAt = DateTime.UtcNow };
            _db.MessageReactions.Add(existing);
        }
        else
        {
            existing.Emoji = req.Emoji;
            existing.CreatedAt = DateTime.UtcNow;
        }
        await _db.SaveChangesAsync();
        return Ok(new MessageReactionDto(messageId, MyId, req.Emoji));
    }

    // DELETE api/Chats/messages/{messageId}/reactions: go cam xuc.
    [HttpDelete("messages/{messageId}/reactions")]
    public async Task<IActionResult> DeleteReaction(int messageId)
    {
        var existing = await _db.MessageReactions
            .FirstOrDefaultAsync(r => r.MessageId == messageId && r.UserId == MyId);
        if (existing == null) return NotFound(new { message = "Chưa thả cảm xúc cho tin nhắn này" });
        _db.MessageReactions.Remove(existing);
        await _db.SaveChangesAsync();
        return Ok(new { message = "Đã gỡ cảm xúc" });
    }

    // PUT api/Chats/{peerId}/read: danh dau tat ca tin cua doi phuong
    // trong doan chat la da xem (goi khi mo / dang o trong man hinh chat).
    [HttpPut("{peerId}/read")]
    public async Task<IActionResult> MarkRead(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var unread = await _db.ChatMessages
            .Where(m => m.ChatId == chatId && m.SenderId == peerId && !m.IsRead)
            .ToListAsync();
        foreach (var m in unread) m.IsRead = true;
        if (unread.Count > 0) await _db.SaveChangesAsync();
        return Ok(new { message = "Đã đánh dấu đã xem", count = unread.Count });
    }

    // POST api/Chats/{peerId}/typing: bao "minh dang nhap" (cap nhat
    // thoi diem, khong tao dong moi moi lan go).
    [HttpPost("{peerId}/typing")]
    public async Task<IActionResult> Typing(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var existing = await _db.ChatTypings.FirstOrDefaultAsync(t => t.ChatId == chatId && t.UserId == MyId);
        if (existing == null)
        {
            _db.ChatTypings.Add(new ChatTyping { ChatId = chatId, UserId = MyId, UpdatedAt = DateTime.UtcNow });
        }
        else
        {
            existing.UpdatedAt = DateTime.UtcNow;
        }
        await _db.SaveChangesAsync();
        return Ok(new { message = "Đang nhập" });
    }

    // GET api/Chats/{peerId}/typing: doi phuong co dang nhap trong
    // 4 giay gan nhat khong.
    [HttpGet("{peerId}/typing")]
    public async Task<IActionResult> IsTyping(string peerId)
    {
        var chatId = PhoneHelper.ChatIdOf(MyId, peerId);
        var recent = DateTime.UtcNow.AddSeconds(-4);
        var typing = await _db.ChatTypings.AnyAsync(t => t.ChatId == chatId && t.UserId == peerId && t.UpdatedAt >= recent);
        return Ok(new { isTyping = typing });
    }

    // POST api/Chats/{peerId}/call-log
    // Giong ChatService.sendCallLog(): dinh dang text giong ban goc
    // "Cuộc gọi video · 02:15" / "Cuộc gọi thoại bị từ chối" / "... nhỡ".
    [HttpPost("{peerId}/call-log")]
    public async Task<IActionResult> CallLog(string peerId, [FromBody] CallLogRequest req)
    {
        if (await _users.FindByIdAsync(peerId) == null)
            return NotFound(new { message = "Không tìm thấy người nhận" });

        var kind = req.IsVideo ? "Cuộc gọi video" : "Cuộc gọi thoại";
        string text;
        if (req.Seconds != null)
        {
            var m = (req.Seconds.Value / 60).ToString("D2");
            var s = (req.Seconds.Value % 60).ToString("D2");
            text = $"{kind} · {m}:{s}";
        }
        else if (req.Outcome == "rejected")
            text = $"{kind} bị từ chối";
        else
            text = $"{kind} nhỡ";

        var dto = await AddMessageAsync(peerId, text, "call", req.IsVideo);
        return Ok(dto);
    }
}
