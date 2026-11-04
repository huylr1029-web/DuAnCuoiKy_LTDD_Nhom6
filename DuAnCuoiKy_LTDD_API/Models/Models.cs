using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Identity;

namespace MessengerCallApi.Models;

// ---------------------------------------------------------------------------
// User: thay cho document users/{uid} tren Firestore.
// Id (string, GUID cua Identity) dong vai tro uid trong app Flutter.
// ---------------------------------------------------------------------------
public class AppUser : IdentityUser
{
    [Required, MaxLength(100)]
    public string Name { get; set; } = "";

    public string AvatarUrl { get; set; } = "";

    public bool Online { get; set; } = false;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? LastSeen { get; set; }
}

// ---------------------------------------------------------------------------
// FriendRequest: thay cho collection friend_requests.
// Ban goc dung doc id "{sender}_{receiver}" va doc nguoc "{receiver}_{sender}".
// O day dung khoa int tu tang, nhung logic kiem tra nguoc / trung lap
// duoc giu nguyen trong FriendRequestsController.
// ---------------------------------------------------------------------------
public class FriendRequest
{
    public int Id { get; set; }

    [Required]
    public string SenderId { get; set; } = "";

    [Required]
    public string ReceiverId { get; set; } = "";

    public string SenderName { get; set; } = "";
    public string ReceiverName { get; set; } = "";

    // pending | accepted | rejected
    public string Status { get; set; } = "pending";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? RespondedAt { get; set; }
}

// ---------------------------------------------------------------------------
// FriendNickname: biet danh rieng ma 1 nguoi dat cho 1 ban.
// Chi nguoi dat moi thay biet danh nay (giong Messenger): OwnerId dat
// cho PeerId, nguoi kia van thay ten that cua OwnerId neu khong tu dat.
// Khi huy ket ban, ca 2 chieu biet danh giua 2 nguoi deu bi xoa.
// ---------------------------------------------------------------------------
public class FriendNickname
{
    public int Id { get; set; }

    [Required]
    public string OwnerId { get; set; } = "";

    [Required]
    public string PeerId { get; set; } = "";

    [Required, MaxLength(100)]
    public string Nickname { get; set; } = "";

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

// ---------------------------------------------------------------------------
// Chat + ChatMessage: thay cho chats/{chatId} va chats/{chatId}/messages.
// ChatId duoc tinh giong ham ChatService.chatIdOf() ben Flutter:
// sap xep 2 uid roi noi bang "_", nen 2 nguoi luon co chung 1 chat.
// ---------------------------------------------------------------------------
public class Chat
{
    [Key]
    public string Id { get; set; } = ""; // chatId

    [Required]
    public string MemberA { get; set; } = "";

    [Required]
    public string MemberB { get; set; } = "";

    public string NameA { get; set; } = "";
    public string NameB { get; set; } = "";

    public string LastMessage { get; set; } = "";
    public string LastSenderId { get; set; } = "";
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public List<ChatMessage> Messages { get; set; } = new();
}

public class ChatMessage
{
    public int Id { get; set; }

    [Required]
    public string ChatId { get; set; } = "";

    [Required]
    public string SenderId { get; set; } = "";

    public string Text { get; set; } = "";

    // text | call
    public string Type { get; set; } = "text";
    public bool IsVideo { get; set; } = false;

    // Da xem: true khi nguoi nhan da mo doan chat (PUT .../read).
    public bool IsRead { get; set; } = false;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// ---------------------------------------------------------------------------
// MessageReaction: cam xuc tha cho 1 tin nhan, moi nguoi chi co
// toi da 1 cam xuc tren 1 tin nhan (doi cam xuc thi ghi de).
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// ChatArchive: luu tru / giau doan chat, CHI RIENG chu so huu.
// OwnerId = nguoi an doan chat, ChatId = doan chat bi an.
// Nguoi kia van thay doan chat binh thuong, tin nhan khong bi xoa.
// Khi co tin nhan moi, archive cua ca 2 ben bi xoa de tin moi khong
// bi giau (xem AddMessageAsync ben ChatsController).
// ---------------------------------------------------------------------------
// Typing: trang thai "dang nhap" cua 1 nguoi trong 1 doan chat.
// Chi luu thoi diem cuoi cung go, GET chi tra true khi trong 4 giay
// gan nhat (de trang thai tu tat neu app dong dot ngot).
public class ChatTyping
{
    public int Id { get; set; }

    [Required]
    public string ChatId { get; set; } = "";

    [Required]
    public string UserId { get; set; } = "";

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class ChatArchive
{
    public int Id { get; set; }

    [Required]
    public string OwnerId { get; set; } = "";

    [Required]
    public string ChatId { get; set; } = "";

    public DateTime ArchivedAt { get; set; } = DateTime.UtcNow;
}

public class MessageReaction
{
    public int Id { get; set; }

    public int MessageId { get; set; }

    [Required]
    public string UserId { get; set; } = "";

    [Required, MaxLength(10)]
    public string Emoji { get; set; } = "";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// ---------------------------------------------------------------------------
// GroupChat: chat nhom, tach rieng khoi Chat 1-1 (chi co MemberA/B).
// Id la Guid khong dau gach. Tin nhan nhom co SenderName snapshot
// de hien ten nguoi gui trong nhom (chat 1-1 khong can vi chi co 2 nguoi).
// ---------------------------------------------------------------------------
public class GroupChat
{
    [Key]
    public string Id { get; set; } = "";

    [Required, MaxLength(100)]
    public string Name { get; set; } = "";

    [Required]
    public string CreatorId { get; set; } = "";

    public string LastMessage { get; set; } = "";

    public string LastSenderId { get; set; } = "";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public List<GroupChatMember> Members { get; set; } = new();
}

public class GroupChatMember
{
    public int Id { get; set; }

    [Required]
    public string GroupChatId { get; set; } = "";

    [Required]
    public string UserId { get; set; } = "";

    [Required]
    public string UserName { get; set; } = "";
}

public class GroupChatMessage
{
    public int Id { get; set; }

    [Required]
    public string GroupChatId { get; set; } = "";

    [Required]
    public string SenderId { get; set; } = "";

    [Required]
    public string SenderName { get; set; } = "";

    [Required]
    public string Text { get; set; } = "";

    public string Type { get; set; } = "text";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public record GroupChatMemberDto(string UserId, string UserName);
public record GroupChatDto(string Id, string Name, string CreatorId, string LastMessage, string LastSenderId, DateTime UpdatedAt, List<GroupChatMemberDto> Members);
public record GroupChatMessageDto(int Id, string GroupChatId, string SenderId, string SenderName, string Text, string Type, DateTime CreatedAt);
public record CreateGroupChatRequest(string Name, List<string> MemberIds);
public record SendGroupChatMessageRequest(string Text, string Type = "text");

public class CreateGroupChatImageRequest
{
    public IFormFile? Image { get; set; }
}

// ---------------------------------------------------------------------------
// GroupCall: cuoc goi nhom, khac Call 1-1 (chi co CallerId / CalleeId).
// Id (dang Guid khong dau gach) cung la ten kenh Agora, tat ca thanh
// vien vao cung 1 kenh nen Agora hien nhieu hinh cung luc.
// Trang thai: ongoing (dang dien ra) / ended (da ket thuc).
// Participant: invited (duoc moi, chua tra loi) / accepted (da vao)
// / declined (tu choi) / left (da roi khoi).
// ---------------------------------------------------------------------------
public class GroupCall
{
    [Key]
    public string Id { get; set; } = "";

    [Required]
    public string CreatorId { get; set; } = "";

    [Required]
    public string CreatorName { get; set; } = "";

    public bool IsVideo { get; set; } = true;

    [Required]
    public string Status { get; set; } = "ongoing";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public List<GroupCallParticipant> Participants { get; set; } = new();
}

public class GroupCallParticipant
{
    public int Id { get; set; }

    [Required]
    public string GroupCallId { get; set; } = "";

    [Required]
    public string UserId { get; set; } = "";

    [Required]
    public string UserName { get; set; } = "";

    [Required]
    public string Status { get; set; } = "invited";
}

public record GroupCallParticipantDto(string UserId, string UserName, string Status);
public record GroupCallDto(string Id, string CreatorId, string CreatorName, bool IsVideo, string Status, DateTime CreatedAt, List<GroupCallParticipantDto> Participants);
public record CreateGroupCallRequest(List<string> ParticipantIds, bool IsVideo = true);

// ---------------------------------------------------------------------------
// Call: thay cho collection calls. CallId cung la ten kenh Agora
// ma 2 ben cung tham gia (ben Flutter da dung callId lam channelId).
// ---------------------------------------------------------------------------
public class Call
{
    [Key]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [Required]
    public string CallerId { get; set; } = "";

    public string CallerName { get; set; } = "";

    [Required]
    public string CalleeId { get; set; } = "";

    public string CalleeName { get; set; } = "";

    public bool IsVideo { get; set; } = false;

    // ringing | accepted | rejected | ended | missed
    public string Status { get; set; } = "ringing";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
}

// ---------------------------------------------------------------------------
// Reel: thay cho collection reels + Firebase Storage.
// Anh / nhac luu trong wwwroot/uploads/reels, URL tra ve la URL tuyet doi
// (giong getDownloadURL() cua Firebase) de Flutter phat truc tiep.
// ---------------------------------------------------------------------------
public class ReelLike
{
    public int Id { get; set; }
    public int ReelId { get; set; }

    [Required]
    public string UserId { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class ReelComment
{
    public int Id { get; set; }
    public int ReelId { get; set; }

    [Required]
    public string AuthorId { get; set; } = "";

    [Required]
    public string AuthorName { get; set; } = "";

    [Required, MaxLength(500)]
    public string Text { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public record ReelCommentDto(int Id, int ReelId, string AuthorId, string AuthorName, string Text, DateTime CreatedAt);
public record AddReelCommentRequest(string Text);

public class Reel
{
    public int Id { get; set; }

    [Required]
    public string AuthorId { get; set; } = "";

    public string AuthorName { get; set; } = "";
    public string Caption { get; set; } = "";
    public string ImageUrl { get; set; } = "";
    public string? MusicUrl { get; set; }
    public string? MusicName { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// ---------------------------------------------------------------------------
// DTOs: chi tra ve nhung truong app Flutter can, khong tra PasswordHash
// hay SecurityStamp cua Identity ra ngoai.
// ---------------------------------------------------------------------------
public record UserDto(string Uid, string Name, string Email, string? Phone, bool Online, DateTime? LastSeen, string AvatarUrl = "");
public record AuthResponse(string Token, UserDto User);
public record RegisterRequest(string Name, string Email, string Password, string Phone);
public record LoginRequest(string Email, string Password);
public record GoogleLoginRequest(string IdToken);
public record ForgotPasswordRequest(string Email);
public record ResetPasswordRequest(string Email, string Token, string NewPassword);
public record SetOnlineRequest(bool Online);

public record ChatDto(
    string ChatId, string PeerId, string PeerName, bool PeerOnline,
    string LastMessage, string LastSenderId, DateTime UpdatedAt, bool IsArchived = false, string PeerAvatarUrl = "");

public record MessageDto(
    int Id, string ChatId, string SenderId, string Text, string Type, bool IsVideo, DateTime CreatedAt, bool IsRead = false);

public record SendMessageRequest(string Text, string Type = "text", bool IsVideo = false);
public record SetReactionRequest(string Emoji);
public record MessageReactionDto(int MessageId, string UserId, string Emoji);

public class CreateChatImageRequest
{
    public IFormFile? Image { get; set; }
}

public class CreateChatVoiceRequest
{
    public IFormFile? Audio { get; set; }
}
public record CallLogRequest(bool IsVideo, string Outcome, int? Seconds);

public record FriendRequestDto(
    int Id, string SenderId, string ReceiverId, string SenderName, string ReceiverName,
    string Status, DateTime CreatedAt, DateTime? RespondedAt);

public record InviteRequest(string ReceiverId);
public record RespondRequest(string Status); // accepted | rejected

public record UpdateNameRequest(string Name);

public class UploadAvatarRequest
{
    public IFormFile? Image { get; set; }
}
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record SetNicknameRequest(string Nickname);
public record FriendNicknameDto(string PeerId, string Nickname);

public record StartCallRequest(string PeerId, bool IsVideo);
public record UpdateCallStatusRequest(string Status); // accepted | rejected | ended | missed

public record ReelDto(
    int Id, string AuthorId, string AuthorName, string Caption,
    string ImageUrl, string? MusicUrl, string? MusicName, DateTime CreatedAt,
    int LikeCount = 0, bool LikedByMe = false, int CommentCount = 0, string AuthorAvatarUrl = "");

// Form dang Reels: phai gom 3 field vao 1 class duy nhat.
// Neu de 2 IFormFile rieng (image, music) lam 2 tham so [FromForm],
// Swashbuckle khi tao swagger.json se loi "An item with the same key
// has already been added. Key: ContentType" va Swagger UI bao 500.
public class CreateReelRequest
{
    public IFormFile? Image { get; set; }
    public IFormFile? Music { get; set; }
    public string Caption { get; set; } = "";
}

// ---------------------------------------------------------------------------
// PhoneHelper: chuan hoa so Viet Nam giong AuthService.normalizePhone()
// ben Flutter: 09... / 03... / 05... / 07... / 08... -> +84...,
// chap nhan ca dang +84... va 84... . Tra ve null neu khong hop le.
// ---------------------------------------------------------------------------
public static class PhoneHelper
{
    public static string? Normalize(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var value = raw.Replace(" ", "").Replace(".", "").Replace("(", "").Replace(")", "").Replace("-", "");
        string digits;
        if (System.Text.RegularExpressions.Regex.IsMatch(value, @"^0[35789][0-9]{8}$"))
            digits = value[1..];
        else if (System.Text.RegularExpressions.Regex.IsMatch(value, @"^\+84[35789][0-9]{8}$"))
            digits = value[3..];
        else if (System.Text.RegularExpressions.Regex.IsMatch(value, @"^84[35789][0-9]{8}$"))
            digits = value[2..];
        else
            return null;
        return "+84" + digits;
    }

    public static string ChatIdOf(string a, string b) =>
        string.CompareOrdinal(a, b) < 0 ? $"{a}_{b}" : $"{b}_{a}";
}
