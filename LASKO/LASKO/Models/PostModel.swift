import Foundation

struct Post: Identifiable, Codable {
    let id: String
    let content: String
    let author: String
    let timestamp: Date
    let likes: Int
    var replies: Int
    let isLiked: Bool
    let userRank: String // Bronze, Silver, Gold, Platinum, Diamond
    let avatarURL: String?
    let parentCode: String?
    let tlsAddress: String? // Store the original TLS address for filtering
    let profileName: String? // Zeroa display name from API / post body
    let broadcastCount: Int // For comment ranking (2 points each)
    let tlsCount: Int // For comment ranking (3 points each)
    let followerCount: Int // For comment ranking priority (second tier)
    /// Unique key for feed rows (announce reposts share `id` with the original post).
    let feedKey: String
    let announcedBy: String?
    let announcedByProfileName: String?
    let announcedAt: Date?
    
    var isAnnounceRepost: Bool { announcedBy != nil }
    var isReply: Bool { !(parentCode?.isEmpty ?? true) }
    
    // Computed property for comment ranking points
    var points: Int {
        return likes + (broadcastCount * 2) + (tlsCount * 3)
    }
    
    init(
        id: String = UUID().uuidString,
        content: String,
        author: String,
        timestamp: Date = Date(),
        likes: Int = 0,
        replies: Int = 0,
        isLiked: Bool = false,
        userRank: String = "Bronze",
        avatarURL: String? = nil,
        parentCode: String? = nil,
        tlsAddress: String? = nil,
        profileName: String? = nil,
        broadcastCount: Int = 0,
        tlsCount: Int = 0,
        followerCount: Int = 0,
        feedKey: String? = nil,
        announcedBy: String? = nil,
        announcedByProfileName: String? = nil,
        announcedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.author = author
        self.timestamp = timestamp
        self.likes = likes
        self.replies = replies
        self.isLiked = isLiked
        self.userRank = userRank
        self.avatarURL = avatarURL
        self.parentCode = parentCode
        self.tlsAddress = tlsAddress
        self.profileName = profileName
        self.broadcastCount = broadcastCount
        self.tlsCount = tlsCount
        self.followerCount = followerCount
        self.feedKey = feedKey ?? id
        self.announcedBy = announcedBy
        self.announcedByProfileName = announcedByProfileName
        self.announcedAt = announcedAt
    }
}

// Mock data for development
extension Post {
    static let mockPosts = [
        Post(content: "Just deployed my first decentralized social media post! 🚀 #LASKO #Telestai", author: "crypto_dev", likes: 42, replies: 5, userRank: "Diamond", broadcastCount: 3, tlsCount: 2, followerCount: 150),
        Post(content: "Privacy shouldn't be a luxury. That's why I'm building on LASKO.", author: "privacy_advocate", likes: 28, replies: 3, userRank: "Platinum", broadcastCount: 1, tlsCount: 1, followerCount: 89),
        Post(content: "The future of social media is decentralized. No more algorithm manipulation!", author: "web3_builder", likes: 67, replies: 12, userRank: "Gold", broadcastCount: 5, tlsCount: 3, followerCount: 234),
        Post(content: "Testing the LASKO platform. So far, so good! The UI is clean and the experience is smooth.", author: "early_adopter", likes: 15, replies: 2, userRank: "Silver", broadcastCount: 0, tlsCount: 0, followerCount: 45),
        Post(content: "Blockchain-powered social media is the way forward. LASKO is leading the charge.", author: "blockchain_expert", likes: 89, replies: 8, userRank: "Bronze", broadcastCount: 2, tlsCount: 1, followerCount: 67)
    ]
}
