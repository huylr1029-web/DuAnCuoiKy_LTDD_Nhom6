using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Data;
using MessengerCallApi.Models;

namespace MessengerCallApi.Controllers;

// Thay cho collection reels + Firebase Storage.
// Anh / nhac gui len bang multipart/form-data, luu vao
// wwwroot/uploads/reels/{authorId}/{reelId}/... va tra ve URL tuyet doi.
// Gioi han: anh bat buoc (giong ban goc: phai chon anh moi dang),
// nhac khong bat buoc.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ReelsController : ControllerBase
{
    private readonly ApplicationDbContext _db;
    private readonly UserManager<AppUser> _users;
    private readonly IWebHostEnvironment _env;

    public ReelsController(ApplicationDbContext db, UserManager<AppUser> users, IWebHostEnvironment env)
    {
        _db = db;
        _users = users;
        _env = env;
    }

    private string MyId => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";

    private static ReelDto ToDto(Reel r) =>
        new(r.Id, r.AuthorId, r.AuthorName, r.Caption, r.ImageUrl, r.MusicUrl, r.MusicName, r.CreatedAt);

    private async Task<List<ReelDto>> ToDtos(List<Reel> reels)
    {
        var ids = reels.Select(r => r.Id).ToList();
        var authorIds = reels.Select(r => r.AuthorId).Distinct().ToList();
        var authors = await _users.Users.Where(u => authorIds.Contains(u.Id)).ToListAsync();
        var likes = await _db.ReelLikes.Where(l => ids.Contains(l.ReelId)).ToListAsync();
        var comments = await _db.ReelComments.Where(c => ids.Contains(c.ReelId)).ToListAsync();
        return reels.Select(r =>
        {
            var author = authors.FirstOrDefault(u => u.Id == r.AuthorId);
            return new ReelDto(
                r.Id, r.AuthorId, r.AuthorName, r.Caption, r.ImageUrl, r.MusicUrl, r.MusicName, r.CreatedAt,
                likes.Count(l => l.ReelId == r.Id),
                likes.Any(l => l.ReelId == r.Id && l.UserId == MyId),
                comments.Count(c => c.ReelId == r.Id),
                author?.AvatarUrl ?? "");
        }).ToList();
    }

    private string AbsoluteUrl(string relativePath) =>
        $"{Request.Scheme}://{Request.Host}/{relativePath.Replace('\\', '/')}";

    // GET api/Reels : moi nhat truoc, toi da 50 (giong limit(50) ben Flutter).
    [HttpGet]
    public async Task<IActionResult> All()
    {
        var list = await _db.Reels
            .OrderByDescending(r => r.CreatedAt)
            .ThenByDescending(r => r.Id)
            .Take(50)
            .ToListAsync();
        return Ok(await ToDtos(list));
    }

    // GET api/Reels/my : bai cua chinh minh (ProfileTab).
    [HttpGet("my")]
    public async Task<IActionResult> Mine()
    {
        var list = await _db.Reels
            .Where(r => r.AuthorId == MyId)
            .OrderByDescending(r => r.CreatedAt)
            .ThenByDescending(r => r.Id)
            .ToListAsync();
        return Ok(await ToDtos(list));
    }

    // GET api/Reels/user/{userId}
    [HttpGet("user/{userId}")]
    public async Task<IActionResult> ByUser(string userId)
    {
        var list = await _db.Reels
            .Where(r => r.AuthorId == userId)
            .OrderByDescending(r => r.CreatedAt)
            .ThenByDescending(r => r.Id)
            .ToListAsync();
        return Ok(await ToDtos(list));
    }

    // POST api/Reels/{id}/like: thich (da thich thi van ok, khong tang 2 lan).
    [HttpPost("{id}/like")]
    public async Task<IActionResult> Like(int id)
    {
        if (!await _db.Reels.AnyAsync(r => r.Id == id)) return NotFound(new { message = "Không tìm thấy bài đăng" });
        if (!await _db.ReelLikes.AnyAsync(l => l.ReelId == id && l.UserId == MyId))
        {
            _db.ReelLikes.Add(new ReelLike { ReelId = id, UserId = MyId, CreatedAt = DateTime.UtcNow });
            await _db.SaveChangesAsync();
        }
        return Ok(new { message = "Đã thích" });
    }

    // DELETE api/Reels/{id}/like: bo thich.
    [HttpDelete("{id}/like")]
    public async Task<IActionResult> Unlike(int id)
    {
        var existing = await _db.ReelLikes.FirstOrDefaultAsync(l => l.ReelId == id && l.UserId == MyId);
        if (existing == null) return NotFound(new { message = "Bạn chưa thích bài này" });
        _db.ReelLikes.Remove(existing);
        await _db.SaveChangesAsync();
        return Ok(new { message = "Đã bỏ thích" });
    }

    // GET api/Reels/{id}/comments: binh luan moi nhat truoc.
    [HttpGet("{id}/comments")]
    public async Task<IActionResult> Comments(int id)
    {
        if (!await _db.Reels.AnyAsync(r => r.Id == id)) return NotFound(new { message = "Không tìm thấy bài đăng" });
        var list = await _db.ReelComments
            .Where(c => c.ReelId == id)
            .OrderByDescending(c => c.CreatedAt)
            .ThenByDescending(c => c.Id)
            .ToListAsync();
        return Ok(list.Select(c => new ReelCommentDto(c.Id, c.ReelId, c.AuthorId, c.AuthorName, c.Text, c.CreatedAt)));
    }

    // POST api/Reels/{id}/comments {text}: binh luan, toi da 500 ky tu.
    [HttpPost("{id}/comments")]
    public async Task<IActionResult> AddComment(int id, [FromBody] AddReelCommentRequest req)
    {
        var text = (req.Text ?? "").Trim();
        if (string.IsNullOrWhiteSpace(text) || text.Length > 500)
            return BadRequest(new { message = "Bình luận không được để trống và tối đa 500 ký tự" });
        if (!await _db.Reels.AnyAsync(r => r.Id == id)) return NotFound(new { message = "Không tìm thấy bài đăng" });
        var me = await _users.FindByIdAsync(MyId);
        if (me == null) return Unauthorized();
        var comment = new ReelComment { ReelId = id, AuthorId = MyId, AuthorName = me.Name, Text = text, CreatedAt = DateTime.UtcNow };
        _db.ReelComments.Add(comment);
        await _db.SaveChangesAsync();
        return Ok(new ReelCommentDto(comment.Id, comment.ReelId, comment.AuthorId, comment.AuthorName, comment.Text, comment.CreatedAt));
    }

    // POST api/Reels (multipart/form-data)
    // Form fields: image (file, bat buoc), music (file, tuy chon), caption (text).
    [HttpPost]
    [RequestSizeLimit(50 * 1024 * 1024)]
    public async Task<IActionResult> Create([FromForm] CreateReelRequest req)
    {
        var image = req.Image;
        var music = req.Music;
        var caption = req.Caption ?? "";
        if (image == null || image.Length == 0)
            return BadRequest(new { message = "Hãy chọn một ảnh" });

        var me = await _users.FindByIdAsync(MyId);
        if (me == null) return Unauthorized();

        var reel = new Reel
        {
            AuthorId = MyId,
            AuthorName = me.Name,
            Caption = caption.Trim(),
            CreatedAt = DateTime.UtcNow,
        };
        _db.Reels.Add(reel);
        await _db.SaveChangesAsync(); // can Id truoc khi tao thu muc

        var folder = Path.Combine(_env.WebRootPath ?? "wwwroot",
            "uploads", "reels", MyId, reel.Id.ToString());
        Directory.CreateDirectory(folder);

        async Task<string> SaveFile(IFormFile file, string fileName)
        {
            var path = Path.Combine(folder, fileName);
            await using var stream = System.IO.File.Create(path);
            await file.CopyToAsync(stream);
            return $"uploads/reels/{MyId}/{reel.Id}/{fileName}";
        }

        reel.ImageUrl = AbsoluteUrl(await SaveFile(image, "image.jpg"));
        if (music != null && music.Length > 0)
        {
            var ext = Path.GetExtension(music.FileName);
            if (string.IsNullOrWhiteSpace(ext)) ext = ".mp3";
            reel.MusicUrl = AbsoluteUrl(await SaveFile(music, "music" + ext));
            reel.MusicName = music.FileName;
        }
        await _db.SaveChangesAsync();
        return Ok(ToDto(reel));
    }
}
