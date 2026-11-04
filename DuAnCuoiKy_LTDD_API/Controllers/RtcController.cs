using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using AgoraIO.Media;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Data;

namespace MessengerCallApi.Controllers;

[ApiController, Authorize]
[Route("api/Rtc")]
public class RtcController(ApplicationDbContext db, IConfiguration config) : ControllerBase
{
    public record TokenRequest(string CallId, bool IsGroup = false);

    [HttpGet("status")]
    public IActionResult Status() => Ok(new
    {
        configured = config["Agora:AppId"]?.Length == 32 && config["Agora:AppCertificate"]?.Length == 32
    });

    [HttpPost("token")]
    public async Task<IActionResult> Token(TokenRequest req)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        if (req.IsGroup)
        {
            if (!await db.GroupCalls.AnyAsync(c => c.Id == req.CallId && c.Status != "ended" &&
                c.Participants.Any(p => p.UserId == userId && p.Status == "accepted")))
                return Forbid();
        }
        else
        {
            if (!await db.Calls.AnyAsync(c => c.Id == req.CallId &&
                (c.Status == "ringing" || c.Status == "accepted") &&
                (c.CallerId == userId || c.CalleeId == userId))) return Forbid();
        }
        var appId = config["Agora:AppId"];
        var certificate = config["Agora:AppCertificate"];
        if (string.IsNullOrWhiteSpace(appId) || appId.Length != 32 ||
            string.IsNullOrWhiteSpace(certificate) || certificate.Length != 32)
            return StatusCode(503, new { message = "Backend chưa cấu hình Agora AppId/AppCertificate." });
        // Stable nonzero UID lets both participants renew the same RTC identity.
        var uid = BitConverter.ToUInt32(SHA256.HashData(Encoding.UTF8.GetBytes(userId)), 0);
        if (uid == 0) uid = 1;
        var token = RtcTokenBuilder2.buildTokenWithUid(appId, certificate, req.CallId, uid,
            RtcTokenBuilder2.Role.RolePublisher, 3600, 3600);
        if (string.IsNullOrWhiteSpace(token))
            return StatusCode(503, new { message = "Không tạo được token Agora. Kiểm tra cấu hình." });
        return Ok(new { appId, channelId = req.CallId, uid, token, expiresIn = 3600 });
    }
}
