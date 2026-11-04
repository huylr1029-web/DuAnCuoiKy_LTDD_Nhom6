using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using System.Security.Claims;

namespace MessengerCallApi.Hubs;

// ---------------------------------------------------------------------------
// SignalR thay cho Firestore snapshots() (realtime).
// - Moi user vao nhom "user_{uid}" de nhan cuoc goi den, trang thai cuoc goi.
// - Moi chat vao nhom "chat_{chatId}" de nhan tin nhan moi.
// Ben Flutter dung package signalr_netcore, ket noi toi /hubs/chat
// kem header Authorization: Bearer <token> hoac ?access_token=<token>.
// ---------------------------------------------------------------------------
[Authorize]
public class ChatHub : Hub
{
    private static string UserId(ClaimsPrincipal? user) =>
        user?.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    public override async Task OnConnectedAsync()
    {
        var uid = UserId(Context.User);
        if (!string.IsNullOrEmpty(uid))
            await Groups.AddToGroupAsync(Context.ConnectionId, $"user_{uid}");
        await base.OnConnectedAsync();
    }

    public async Task JoinChat(string chatId)
    {
        var uid = UserId(Context.User);
        var parts = chatId.Split('_');
        if (parts.Length != 2 || !parts.Contains(uid))
            throw new HubException("Bạn không phải thành viên cuộc trò chuyện.");
        await Groups.AddToGroupAsync(Context.ConnectionId, $"chat_{chatId}");
    }

    public async Task LeaveChat(string chatId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"chat_{chatId}");
    }
}
