using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using MessengerCallApi.Models;

namespace MessengerCallApi.Data;

public class ApplicationDbContext : IdentityDbContext<AppUser>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }

    public DbSet<FriendRequest> FriendRequests => Set<FriendRequest>();
    public DbSet<FriendNickname> FriendNicknames => Set<FriendNickname>();
    public DbSet<Chat> Chats => Set<Chat>();
    public DbSet<ChatMessage> ChatMessages => Set<ChatMessage>();
    public DbSet<MessageReaction> MessageReactions => Set<MessageReaction>();
    public DbSet<ChatArchive> ChatArchives => Set<ChatArchive>();
    public DbSet<GroupCall> GroupCalls => Set<GroupCall>();
    public DbSet<GroupCallParticipant> GroupCallParticipants => Set<GroupCallParticipant>();
    public DbSet<GroupChat> GroupChats => Set<GroupChat>();
    public DbSet<GroupChatMember> GroupChatMembers => Set<GroupChatMember>();
    public DbSet<GroupChatMessage> GroupChatMessages => Set<GroupChatMessage>();
    public DbSet<ReelLike> ReelLikes => Set<ReelLike>();
    public DbSet<ReelComment> ReelComments => Set<ReelComment>();
    public DbSet<ChatTyping> ChatTypings => Set<ChatTyping>();
    public DbSet<Call> Calls => Set<Call>();
    public DbSet<Reel> Reels => Set<Reel>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);

        // 1 chat chi co 2 thanh vien, tim nhanh theo thanh vien.
        builder.Entity<Chat>().HasIndex(c => c.MemberA);
        builder.Entity<Chat>().HasIndex(c => c.MemberB);
        builder.Entity<Chat>()
            .HasMany(c => c.Messages)
            .WithOne()
            .HasForeignKey(m => m.ChatId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.Entity<ChatMessage>().HasIndex(m => new { m.ChatId, m.CreatedAt });
        builder.Entity<MessageReaction>().HasIndex(r => new { r.MessageId, r.UserId }).IsUnique();
        builder.Entity<ChatArchive>().HasIndex(a => new { a.OwnerId, a.ChatId }).IsUnique();
        builder.Entity<ReelLike>().HasIndex(l => new { l.ReelId, l.UserId }).IsUnique();
        builder.Entity<ChatTyping>().HasIndex(t => new { t.ChatId, t.UserId }).IsUnique();
        builder.Entity<FriendRequest>().HasIndex(f => new { f.SenderId, f.ReceiverId });
        builder.Entity<FriendNickname>().HasIndex(n => new { n.OwnerId, n.PeerId }).IsUnique();
        builder.Entity<FriendRequest>().HasIndex(f => f.ReceiverId);
        builder.Entity<Call>().HasIndex(c => c.CallerId);
        builder.Entity<Call>().HasIndex(c => c.CalleeId);
        builder.Entity<Reel>().HasIndex(r => r.AuthorId);
        builder.Entity<Reel>().HasIndex(r => r.CreatedAt);

        // So dien thoai chuan hoa +84... khong duoc trung (giong check ben Flutter).
        // SQLite khong ep unique tren null tot nhu SQL Server, nen controller
        // van kiem tra trung lap bang code truoc khi tao user.
        builder.Entity<AppUser>().HasIndex(u => u.PhoneNumber);
    }
}
