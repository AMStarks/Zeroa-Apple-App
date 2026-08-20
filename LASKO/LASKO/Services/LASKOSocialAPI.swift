import Foundation
import UIKit

// MARK: - Social graph models (Halo /api/social)

struct LASKOSocialProfile: Identifiable, Equatable {
    let address: String
    let profileName: String?
    var id: String { address }

    var displayName: String {
        if let profileName, !profileName.isEmpty { return profileName }
        if address.count > 12 {
            return "\(address.prefix(6))…\(address.suffix(4))"
        }
        return address
    }
}

struct LASKOSocialStatus: Equatable {
    var followingCount: Int
    var followerCount: Int
    var isFollowing: Bool
}

struct LASKOInboxItem: Identifiable, Equatable {
    let id: String
    let type: String
    let parentId: String?
    let replyId: String?
    let fromAddress: String?
    let preview: String?
    let at: Int64
}

extension LASKOService {
    private var socialBaseURL: URL {
        URL(string: "https://halo.telestai.io/api/social")!
    }

    func postingKeyExpiresAtMs() -> Int64? {
        guard let defaults = AppGroupsService.shared.sharedDefaults else { return nil }
        if let v = defaults.object(forKey: "lasko_posting_expires_at_ms") as? Int64 { return v }
        if let v = defaults.object(forKey: "lasko_posting_expires_at_ms") as? Int { return Int64(v) }
        return nil
    }

    func postingKeyMinutesRemaining() -> Int? {
        guard let exp = postingKeyExpiresAtMs() else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let ms = exp - now
        guard ms > 0 else { return 0 }
        return Int(ms / 60_000)
    }

    func observePostingKeySignals() {
        let readyName = "com.telestai.zeroa.posting.key.ready" as CFString
        let failedName = "com.telestai.zeroa.posting.key.failed" as CFString
        let readyCallback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { _, _, _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("LASKOPostingKeyReady"), object: nil)
            }
        }
        let failedCallback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { _, _, _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("LASKOPostingKeyFailed"), object: nil)
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil, readyCallback, readyName, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil, failedCallback, failedName, nil, .deliverImmediately
        )
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LASKOPostingKeyReady"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.needsOpenZeroaToSign = false
                self?.errorMessage = nil
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LASKOPostingKeyFailed"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.needsOpenZeroaToSign = true
                self?.errorMessage = "Posting key wasn’t issued. Tap Open Zeroa to finish connecting."
            }
        }
    }

    func fetchSocialStatus(for address: String) async -> LASKOSocialStatus? {
        guard !address.isEmpty else { return nil }
        var comps = URLComponents(url: socialBaseURL.appendingPathComponent("status"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "address", value: address)]
        if let viewer = currentTLSAddress, !viewer.isEmpty {
            items.append(URLQueryItem(name: "viewer", value: viewer))
        }
        comps.queryItems = items
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any] else { return nil }
            let status = LASKOSocialStatus(
                followingCount: (dataObj["followingCount"] as? Int) ?? Int("\(dataObj["followingCount"] ?? 0)") ?? 0,
                followerCount: (dataObj["followerCount"] as? Int) ?? Int("\(dataObj["followerCount"] ?? 0)") ?? 0,
                isFollowing: (dataObj["isFollowing"] as? Bool) ?? false
            )
            await MainActor.run {
                if status.isFollowing {
                    followedAddresses.insert(address)
                } else if currentTLSAddress != nil {
                    followedAddresses.remove(address)
                }
            }
            return status
        } catch {
            print("⚠️ LASKO: social status failed: \(error.localizedDescription)")
            return nil
        }
    }

    func isFollowing(_ address: String?) -> Bool {
        guard let address, !address.isEmpty else { return false }
        return followedAddresses.contains(address)
    }

    @discardableResult
    func follow(address target: String) async -> Bool {
        let ok = await mutateFollow(target: target, method: "POST")
        if ok {
            await MainActor.run { followedAddresses.insert(target) }
        }
        return ok
    }

    @discardableResult
    func unfollow(address target: String) async -> Bool {
        let ok = await mutateFollow(target: target, method: "DELETE")
        if ok {
            await MainActor.run { followedAddresses.remove(target) }
        }
        return ok
    }

    /// Hydrate local follow set from Halo (for green rings across the feed).
    func refreshFollowedAddresses() async {
        guard let address = currentTLSAddress, !address.isEmpty else { return }
        guard let token = await ensureHaloToken() else { return }
        var comps = URLComponents(url: socialBaseURL.appendingPathComponent("following"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = comps.url else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(address, forHTTPHeaderField: "X-TLS-Address")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["data"] as? [[String: Any]] else { return }
            let addrs = Set(rows.compactMap { ($0["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            await MainActor.run { followedAddresses = addrs }
        } catch {
            print("⚠️ LASKO: following list failed: \(error.localizedDescription)")
        }
    }

    private func mutateFollow(target: String, method: String) async -> Bool {
        guard let actor = currentTLSAddress, !actor.isEmpty else {
            errorMessage = "Connect Zeroa to follow people."
            return false
        }
        guard let token = await ensureHaloToken() else {
            errorMessage = "Missing Halo token. Open Zeroa."
            return false
        }
        var request = URLRequest(url: socialBaseURL.appendingPathComponent("follow"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(actor, forHTTPHeaderField: "X-TLS-Address")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "userAddress": actor,
            "targetAddress": target
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                errorMessage = msg ?? "Follow failed (\(code))"
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadFollowingFeed(page: Int = 0) async -> [Post] {
        guard let address = currentTLSAddress, !address.isEmpty else { return [] }
        var comps = URLComponents(url: socialBaseURL.appendingPathComponent("feed"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "30")
        ]
        guard let url = comps.url, let token = await ensureHaloToken() else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(address, forHTTPHeaderField: "X-TLS-Address")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["data"] as? [[String: Any]] else { return [] }
            return rows.compactMap { mapSocialPost($0) }
        } catch {
            print("⚠️ LASKO: following feed failed: \(error.localizedDescription)")
            return []
        }
    }

    func loadInbox(limit: Int = 40) async -> [LASKOInboxItem] {
        guard let address = currentTLSAddress, !address.isEmpty else { return [] }
        guard let token = await ensureHaloToken() else { return [] }
        var comps = URLComponents(url: socialBaseURL.appendingPathComponent("inbox"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = comps.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(address, forHTTPHeaderField: "X-TLS-Address")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["data"] as? [[String: Any]] else { return [] }
            return rows.enumerated().compactMap { idx, row in
                let replyId = row["replyId"] as? String
                let at = (row["at"] as? Int64) ?? Int64("\(row["at"] ?? 0)") ?? 0
                return LASKOInboxItem(
                    id: replyId ?? "\(at)-\(idx)",
                    type: (row["type"] as? String) ?? "reply",
                    parentId: row["parentId"] as? String,
                    replyId: replyId,
                    fromAddress: row["fromAddress"] as? String,
                    preview: row["preview"] as? String,
                    at: at
                )
            }
        } catch {
            print("⚠️ LASKO: inbox failed: \(error.localizedDescription)")
            return []
        }
    }

    private func ensureHaloToken() async -> String? {
        AppGroupsService.shared.sharedDefaults?.synchronize()
        if let token = AppGroupsService.shared.sharedDefaults?.string(forKey: "halo_access_token")
            ?? AppGroupsService.shared.sharedDefaults?.string(forKey: "haloAccessToken"),
           !token.isEmpty {
            return token
        }
        await prewarmHaloTokenIfPossible()
        AppGroupsService.shared.sharedDefaults?.synchronize()
        return AppGroupsService.shared.sharedDefaults?.string(forKey: "halo_access_token")
            ?? AppGroupsService.shared.sharedDefaults?.string(forKey: "haloAccessToken")
    }

    private func mapSocialPost(_ row: [String: Any]) -> Post? {
        guard let id = row["id"] as? String else { return nil }
        let author = (row["profileName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = (row["userAddress"] as? String) ?? ""
        let content = (row["content"] as? String) ?? ""
        let likes = (row["likesCount"] as? Int) ?? Int("\(row["likesCount"] ?? 0)") ?? 0
        let replies = (row["repliesCount"] as? Int) ?? Int("\(row["repliesCount"] ?? 0)") ?? 0
        let broadcasts = (row["broadcastCount"] as? Int) ?? Int("\(row["broadcastCount"] ?? 0)") ?? 0
        let tls = (row["tlsCount"] as? Int) ?? Int("\(row["tlsCount"] ?? 0)") ?? 0
        let ts: Date = {
            if let s = row["timestamp"] as? String, let ms = Double(s) {
                return Date(timeIntervalSince1970: ms / 1000)
            }
            if let n = row["timestamp"] as? Double {
                return Date(timeIntervalSince1970: n > 1_000_000_000_000 ? n / 1000 : n)
            }
            return Date()
        }()
        return Post(
            id: id,
            content: content,
            author: (author?.isEmpty == false ? author! : String(addr.prefix(8))),
            timestamp: ts,
            likes: likes,
            replies: replies,
            userRank: "Member",
            tlsAddress: addr,
            profileName: author,
            broadcastCount: broadcasts,
            tlsCount: tls,
            followerCount: 0
        )
    }
}
