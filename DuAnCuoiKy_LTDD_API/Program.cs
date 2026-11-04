// Backend ASP.NET Core 8 thay Firebase cho app DuAnCuoiKy_LTDD (Messenger Call).
// Kieu Tuan 6 / Tuan 7: EF Core + Identity + JWT Bearer + Repository khong bat buoc
// (controller dung truc tiep DbContext cho gon, dung kieu Tuan 6 ProductApiController).
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using MessengerCallApi.Data;
using MessengerCallApi.Hubs;
using MessengerCallApi.Models;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

var conn = builder.Configuration.GetConnectionString("DefaultConnection") ?? "";
// May Windows cua sinh vien (Visual Studio): dung SQL Server nhu appsettings.json.
// May Linux / Render / may test khong co SQL Server: dung SQLite khi
// connection string bat dau bang "Data Source=" (giong backend cu).
builder.Services.AddDbContext<ApplicationDbContext>(o =>
{
    if (conn.StartsWith("Data Source=", StringComparison.OrdinalIgnoreCase))
        o.UseSqlite(conn);
    else
        o.UseSqlServer(conn);
});

builder.Services.AddIdentity<AppUser, IdentityRole>()
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();

// Mat khau mac dinh cua Identity kha chat; giu nguyen de khong phai
// sua giao trinh, nhung cho phep mat khau 6 ky tu nhu Firebase
// (Firebase chi yeu cau toi thieu 6 ky tu).
builder.Services.Configure<IdentityOptions>(o =>
{
    o.Password.RequireDigit = false;
    o.Password.RequireLowercase = false;
    o.Password.RequireUppercase = false;
    o.Password.RequireNonAlphanumeric = false;
    o.Password.RequiredLength = 6;
    o.User.RequireUniqueEmail = true;
});

builder.Services.AddControllers();
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedProto;
    // Trust the immediate hosting proxy for scheme only; never use its client IP for rate limits.
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});
builder.Services.AddSignalR();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    // Cho phep nhap token JWT trong Swagger: nut Authorize -> "Bearer <token>".
    c.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Description = "Nhap: Bearer <token>",
    });
    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id = "Bearer",
                },
            },
            Array.Empty<string>()
        },
    });
});

// Demo lop hoc: cho phep Flutter (Android / web) goi tu moi origin.
// Khi dua len that thi thu hep lai chi origin cua app.
builder.Services.AddCors(o => o.AddPolicy("AllowAll", p =>
    p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var jwt = builder.Configuration.GetSection("JWTKey");
if (string.IsNullOrWhiteSpace(jwt["Secret"]) || Encoding.UTF8.GetByteCount(jwt["Secret"]!) < 32)
    throw new InvalidOperationException("Cần cấu hình JWTKey:Secret (biến môi trường JWTKey__Secret trên Render) dài ít nhất 32 byte.");
var key = Encoding.UTF8.GetBytes(jwt["Secret"]!);
builder.Services.AddAuthentication(o =>
{
    o.DefaultAuthenticateScheme = "Bearer";
    o.DefaultChallengeScheme = "Bearer";
})
.AddJwtBearer("Bearer", o =>
{
    o.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwt["ValidIssuer"],
        ValidAudience = jwt["ValidAudience"],
        IssuerSigningKey = new SymmetricSecurityKey(key),
    };
    // SignalR ben Flutter co the gui token qua query ?access_token=
    // vi WebSocket khong gui header Authorization nhu HTTP binh thuong.
    o.Events = new JwtBearerEvents
    {
        OnMessageReceived = context =>
        {
            var accessToken = context.Request.Query["access_token"];
            var path = context.HttpContext.Request.Path;
            if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs/chat"))
                context.Token = accessToken;
            return Task.CompletedTask;
        },
    };
});
builder.Services.AddAuthorization();

var webRoot = Path.GetFullPath(builder.Configuration["Uploads:WebRoot"] ??
    Path.Combine(builder.Environment.ContentRootPath, "wwwroot"));
Directory.CreateDirectory(webRoot);
builder.Environment.WebRootPath = webRoot;
builder.Environment.WebRootFileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(webRoot);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("ok"));

// Tao DB neu chua co (EnsureCreated, khong can chay migration cho bai hoc).
// Luu y: neu sau nay dung migration thi thay bang Migrate().
using (var scope = app.Services.CreateScope())
{
    scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Database.EnsureCreated();
    Directory.CreateDirectory(Path.Combine(app.Environment.WebRootPath ?? "wwwroot", "uploads"));
}

// De thay kiem tra API truc tiep tren link Render (Production):
// bat Swagger luon, khong chi o Development. Day la ban demo cho
// giao vien xem danh sach GET/POST/PUT/DELETE, khong anh huong
// toi du lieu hay bao mat cua app (Swagger chi liet ke endpoint).
app.UseSwagger();
app.UseSwaggerUI();

app.UseForwardedHeaders();
app.UseStaticFiles(); // phuc vu /uploads/reels/... cho Reels
app.UseCors("AllowAll");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHub<ChatHub>("/hubs/chat");
app.Run();

public partial class Program { }
