import Foundation
import CryptoKit

/// Reviewed behavior, rather than instructions taken from an untrusted web page.
public enum WebMorningBehavior: String, Codable, CaseIterable, Sendable {
    case browseFeed, watchVideos, watchStories, readHeadlines, readUnread

    public var displayName: String {
        switch self {
        case .browseFeed: String(localized: "Browse the feed", bundle: .module)
        case .watchVideos: String(localized: "Watch videos", bundle: .module)
        case .watchStories: String(localized: "Watch stories", bundle: .module)
        case .readHeadlines: String(localized: "Read headlines aloud", bundle: .module)
        case .readUnread: String(localized: "Read visible unread information", bundle: .module)
        }
    }

    public var behaviorDescription: String {
        switch self {
        case .browseFeed: String(localized: "MORE reads visible posts and scrolls through your feed at a gentle pace.", bundle: .module)
        case .watchVideos: String(localized: "MORE opens the video feed and moves to the next video after each viewing moment.", bundle: .module)
        case .watchStories: String(localized: "MORE opens your stories and advances through the visible stories.", bundle: .module)
        case .readHeadlines: String(localized: "MORE reads the visible headlines and continues through the page.", bundle: .module)
        case .readUnread: String(localized: "MORE reads the unread information visible in this browser.", bundle: .module)
        }
    }

    public static func availableBehaviors(for site: WebMorningSite) -> [Self] {
        switch site {
        case .instagram: [.browseFeed, .watchVideos, .watchStories]
        case .youtube: [.watchVideos]
        case .tiktok: [.browseFeed, .watchVideos]
        case .twitter, .reddit, .threads: [.browseFeed]
        case .facebook: [.browseFeed, .watchStories]
        case .news: [.readHeadlines]
        case .whatsapp: [.readUnread]
        case .gmail: []
        }
    }

    public static func permitsLikes(for site: WebMorningSite, behavior: Self) -> Bool {
        availableBehaviors(for: site).contains(behavior) &&
            [.instagram, .youtube, .tiktok, .twitter, .reddit, .facebook, .threads].contains(site)
    }

    public static func defaultBehavior(for site: WebMorningSite) -> Self? {
        switch site {
        case .news: .readHeadlines
        case .whatsapp: .readUnread
        case .gmail: nil
        case .youtube, .tiktok: .watchVideos
        default: .browseFeed
        }
    }
}

public struct WebMorningExecutionPlan: Sendable, Equatable {
    public let sessionID: UUID
    public let stepID: UUID
    public let behavior: WebMorningBehavior
    public let likesAllowed: Bool
    public let maximumLikes: Int
    public let dwellSeconds: TimeInterval
    public let initialObservedContentCount: Int
    public let initialConfirmedLikeCount: Int

    public init(sessionID: UUID, stepID: UUID, behavior: WebMorningBehavior,
                likesAllowed: Bool = false, maximumLikes: Int = 3, dwellSeconds: TimeInterval = 12,
                initialObservedContentCount: Int = 0, initialConfirmedLikeCount: Int = 0) {
        self.sessionID = sessionID; self.stepID = stepID; self.behavior = behavior
        self.likesAllowed = likesAllowed; self.maximumLikes = min(3, max(0, maximumLikes))
        self.dwellSeconds = dwellSeconds.isFinite ? min(60, max(5, dwellSeconds)) : 12
        self.initialObservedContentCount = min(100_000, max(0, initialObservedContentCount))
        self.initialConfirmedLikeCount = min(3, max(0, initialConfirmedLikeCount))
    }
}

public enum WebMorningExecutionState: String, Codable, Sendable, Equatable {
    case waitingForPage, running, performingAction, paused, needsSignIn, needsChoice, unavailable, uncertainAction, finished, cancelled
}

/// Counts mean observed content and visible effects, never elapsed timers or page loads.
/// The caller must check both IDs before changing the active session.
public struct WebMorningExecutionEvent: Sendable, Equatable {
    public let sessionID: UUID
    public let stepID: UUID
    public let state: WebMorningExecutionState
    public let observedContentCount: Int
    public let confirmedLikeCount: Int
    public let spokenText: [String]
    public init(plan: WebMorningExecutionPlan, state: WebMorningExecutionState,
                observedContentCount: Int, confirmedLikeCount: Int, spokenText: [String] = []) {
        sessionID = plan.sessionID; stepID = plan.stepID; self.state = state
        self.observedContentCount = observedContentCount; self.confirmedLikeCount = confirmedLikeCount
        self.spokenText = spokenText
    }
}

public struct WebMorningPageObservation: Decodable, Sendable, Equatable {
    public enum Status: String, Decodable, Sendable { case ready, loading, signin, choice, empty, unavailable }
    public let status: Status
    public let fingerprint: String?
    public let contentID: String?
    public let text: [String]?
    public let liked: Bool?
    public let canLike: Bool?
    public let canAdvance: Bool?
    public let storyRoute: String?
    public let mediaPlaying: Bool?
    public let scrollOffset: Double?
    public let consentCanDismiss: Bool?

    public static func parse(_ value: Any?) -> Self? {
        guard let value = value as? String, value.utf8.count <= 12_000,
              let data = value.data(using: .utf8), let result = try? JSONDecoder().decode(Self.self, from: data),
              (result.fingerprint?.count ?? 0) <= 128, (result.contentID?.count ?? 0) <= 512,
              (result.storyRoute?.count ?? 0) <= 512,
              result.scrollOffset.map({ $0.isFinite && $0 >= 0 && $0 <= 100_000_000 }) != false,
              (result.text?.count ?? 0) <= 5,
              result.text?.allSatisfy({ !$0.isEmpty && $0.count <= 600 }) != false,
              result.status != .ready || result.fingerprint?.isEmpty == false else { return nil }
        return result
    }
}

/// An attempted like survives a view dismissal or crash. Only its positive visible
/// state can settle it; a missing button never authorizes another toggle.
public struct WebMorningLikeJournal: Sendable {
    private struct Entry: Codable, Sendable { let key: String; var confirmed: Bool; let sessionID: UUID?; let stepID: UUID? }
    private let file: AtomicJSONFile<[Entry]>
    public init(directory: URL) {
        file = AtomicJSONFile(url: directory.appendingPathComponent("browser-action-journal.json"), maximumBytes: 1_000_000)
    }
    public static func key(site: WebMorningSite, contentID: String) -> String {
        SHA256.hash(data: Data("\(site.rawValue):\(contentID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return [] }
        let entries = try file.load()
        guard entries.count <= 10_000, Set(entries.map(\.key)).count == entries.count,
              entries.allSatisfy({ $0.key.count == 64 && $0.key.allSatisfy(\.isHexDigit) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entries
    }
    public func hasAttempt(_ key: String) throws -> Bool { try entries().contains { $0.key == key } }
    public func unresolvedKeys(sessionID: UUID? = nil, stepID: UUID? = nil) throws -> [String] {
        try entries().filter { !$0.confirmed && (sessionID == nil || $0.sessionID == sessionID) &&
            (stepID == nil || $0.stepID == stepID) }.map(\.key)
    }
    public func attemptCount(sessionID: UUID, stepID: UUID) throws -> Int {
        try entries().filter { $0.sessionID == sessionID && $0.stepID == stepID }.count
    }
    public func confirmedCount(sessionID: UUID, stepID: UUID) throws -> Int {
        try entries().filter { $0.sessionID == sessionID && $0.stepID == stepID && $0.confirmed }.count
    }
    /// Write before touching the remote page. Never reserve the same content twice.
    @discardableResult public func reserve(_ key: String, sessionID: UUID? = nil, stepID: UUID? = nil) throws -> Bool {
        var entries = try entries()
        guard !entries.contains(where: { $0.key == key }), !entries.contains(where: { !$0.confirmed }),
              entries.count < 10_000, key.count == 64, key.allSatisfy(\.isHexDigit) else { return false }
        entries.append(.init(key: key, confirmed: false, sessionID: sessionID, stepID: stepID)); try file.save(entries); return true
    }
    public func confirm(_ key: String) throws {
        var entries = try entries()
        guard let index = entries.firstIndex(where: { $0.key == key }) else { throw CocoaError(.fileReadCorruptFile) }
        entries[index].confirmed = true; try file.save(entries)
    }
}

public enum WebMorningExecutionPolicy {
    public static func permits(site: WebMorningSite, url: URL?) -> Bool {
        guard let url, WebMorningSite(url: url) == site, !WebMorningPolicy.isSignInPage(url), site != .gmail else { return false }
        return true
    }

    public static func entryURL(site: WebMorningSite, behavior: WebMorningBehavior) -> URL? {
        guard behavior == .watchVideos else { return nil }
        switch site {
        case .instagram: return site.table.feedURL
        case .youtube: return site.table.feedURL
        case .tiktok: return URL(string: "https://www.tiktok.com/")
        default: return nil
        }
    }

    /// All observations and commands run in an isolated world. Content is data:
    /// no page text is evaluated and no arbitrary selector or script is accepted.
    public static func script(site: WebMorningSite, behavior: WebMorningBehavior,
                              command: String = "observe", fingerprint: String? = nil,
                              likesAllowed: Bool = false, expiresAt: Date = Date().addingTimeInterval(2)) -> String {
        guard WebMorningBehavior.availableBehaviors(for: site).contains(behavior) else {
            return "JSON.stringify({status:'unavailable'})"
        }
        let selectors: [String]
        switch site {
        case .instagram: selectors = behavior == .watchStories ? ["[role=dialog] video", "[role=dialog] img[alt]", "main video"] : ["article", "main video"]
        case .tiktok: selectors = ["[data-e2e=\"recommend-list-item-container\"]", "[data-e2e=\"browse-video\"]", "main video"]
        case .youtube: selectors = ["ytd-reel-video-renderer[is-active]", "ytm-reel-item-renderer", "#shorts-player video", "video"]
        case .twitter: selectors = ["article[data-testid=\"tweet\"]"]
        case .reddit: selectors = ["shreddit-post", "[data-testid=\"post-container\"]"]
        case .facebook: selectors = behavior == .watchStories ? ["[role=dialog] video", "[role=dialog] img[alt]"] : ["[role=feed] [role=article]", "[role=article]"]
        case .threads: selectors = ["[data-pressable-container=true]", "article"]
        case .news: selectors = site.table.headlines ?? []
        case .whatsapp: selectors = ["#pane-side [role=row]"]
        case .gmail: selectors = []
        }
        return #"""
        (() => {
          const out = x => JSON.stringify(x), command = \#(json(command)), expected = \#(json(fingerprint));
          if (Date.now() > \#(Int(expiresAt.timeIntervalSince1970 * 1000))) return out({status:'unavailable'});
          if (window.top !== window || location.protocol !== 'https:' ||
              !\#(json(site.table.allowedHosts.sorted())).includes(location.hostname.toLowerCase()) ||
              location.port && location.port !== '443' || location.username || location.password) return out({status:'unavailable'});
          if (\#(json(WebMorningPolicy.signInPathFragments)).some(p => (location.pathname.toLowerCase() + '/').includes(p))) return out({status:'signin'});
          if (document.hidden) return out({status:'unavailable'});
          const visible = e => {
            if (!e) return false; const r=e.getBoundingClientRect(), s=getComputedStyle(e);
            if (!(r.width>0 && r.height>0 && r.bottom>0 && r.top<innerHeight && s.visibility!=='hidden' && s.display!=='none')) return false;
            if (typeof document.elementFromPoint==='function') {
              const x=Math.max(1,Math.min(innerWidth-1,r.left+r.width/2)), y=Math.max(1,Math.min(innerHeight-1,(Math.max(0,r.top)+Math.min(innerHeight,r.bottom))/2));
              const hit=document.elementFromPoint(x,y);
              if (!hit || !(hit===e || e.contains(hit) || hit.contains(e))) return false;
            }
            return true;
          };
          const all = (root, selectors) => selectors.flatMap(s => { try { return Array.from(root.querySelectorAll(s)); } catch (_) { return []; } });
          if (all(document, ['input[type=password]','input[autocomplete=one-time-code]','input[autocomplete=current-password]','form[action*="login" i]']).some(visible)) return out({status:'signin'});
          if (document.readyState === 'loading') return out({status:'loading'});
          const clean = x => (x || '').replace(/\s+/g,' ').trim();
          const hash = s => { let h=2166136261; for(let i=0;i<s.length;i++) { h ^= s.charCodeAt(i); h = Math.imul(h,16777619); } return (h>>>0).toString(16); };
          // Privacy-preserving dismissal only: never grant tracking consent.
          const consentNames=['continuer sans accepter','continue without accepting','tout refuser','refuser tout','reject all','reject optional cookies'];
          const consent=all(document,['#didomi-host button','#didomi-host a','[role=dialog] button','[role=dialog] a'])
            .filter(visible).find(e=>consentNames.includes(clean(e.getAttribute('aria-label')||e.innerText).replace(/[›→]$/u,'').trim().toLowerCase()));
          if (command==='rejectConsent') {
            if (expected!=='consent' || !consent) return out({status:'unavailable'});
            consent.click(); return out({status:'dispatched'});
          }
          if (consent) return out({status:'loading',fingerprint:'consent',consentCanDismiss:true});
          const choiceLabels=all(document,['button','a','[role=button]']).filter(visible)
            .map(e=>clean(e.getAttribute('aria-label')||e.innerText).toLowerCase());
          const accepts=choiceLabels.some(t=>['accepter et continuer','accept and continue','accepter les cookies','tout accepter','accept all','accept all cookies'].includes(t));
          const personalChoice=choiceLabels.some(t=>["s’abonner","s'abonner",'subscribe','se connecter','sign in','paramétrer','manage preferences','personnaliser mes choix'].includes(t));
          if (accepts && personalChoice) return out({status:'choice'});
          const sameRoute = href => { try { const u=new URL(href, location.href); return u.protocol==='https:' && \#(json(site.table.allowedHosts.sorted())).includes(u.hostname.toLowerCase()) && !u.username && !u.password && (!u.port || u.port==='443') && !\#(json(WebMorningPolicy.signInPathFragments)).some(p=>(u.pathname.toLowerCase()+'/').includes(p)) ? u.pathname : null; } catch (_) { return null; } };
          const behavior = \#(json(behavior.rawValue)), site = \#(json(site.rawValue));
          let nodes = [...new Set(all(document, \#(json(selectors))).filter(visible))];
          if (site==='whatsapp') {
            const loadedRows=nodes.length;
            nodes=nodes.filter(e=>e.querySelector('span[aria-label*="unread" i],span[aria-label*="non lu" i]'));
            if (!nodes.length && loadedRows && command==='observe') return out({status:'ready',fingerprint:'no-visible-unread',text:[\#(json(AppLanguage.isFrench ? "Aucune conversation non lue visible." : "No unread conversations are visible."))],canAdvance:false});
          }
          if (!nodes.length) {
            if (behavior==='watchStories') {
              const link = all(document,['a[href^="/stories/"]']).find(visible), route=link ? sameRoute(link.href) : null;
              if (route) return out({status:'ready',fingerprint:hash(route),storyRoute:route,canAdvance:false});
            }
            return out({status:document.querySelector('[aria-busy=true],[role=progressbar]') ? 'loading' : 'empty'});
          }
          nodes.sort((a,b)=>Math.abs(a.getBoundingClientRect().top+a.getBoundingClientRect().height/2-innerHeight/2)-Math.abs(b.getBoundingClientRect().top+b.getBoundingClientRect().height/2-innerHeight/2));
          let item = nodes[0];
          const text = clean(item.innerText || item.textContent).slice(0,600);
          const links = all(item,['a[href]']);
          const contentLink = links.map(a=>sameRoute(a.href)).find(p=>p && /\/(p|reel|reels|shorts|status|video|comments|post|stories)\//.test(p));
          const contentID = contentLink || item.getAttribute('data-id') || item.getAttribute('post-id') || item.getAttribute('id') || ((/\/(shorts|reel|reels|stories)\//.test(location.pathname)) ? location.pathname : null);
          const video = item.matches('video') ? item : item.querySelector('video');
          const image = item.matches('img') ? item : item.querySelector('img');
          if (video && ['watchVideos','watchStories'].includes(behavior) && video.readyState<2) return out({status:'loading'});
          if (!text && !(video && video.readyState>=2) && !(image && image.complete && image.naturalWidth>0)) return out({status:'empty'});
          const fingerprint = hash(contentID || text+'|'+(video?.currentSrc || image?.currentSrc || ''));
          // Match a control's accessible name exactly; never infer a click from prose.
          const names = e => clean(e.getAttribute('aria-label') || e.querySelector('svg[aria-label]')?.getAttribute('aria-label') || e.getAttribute('title') || e.innerText).toLowerCase();
          const buttons = all(item,['button','[role=button]']).filter(visible);
          const likedNames = ['unlike','ne plus aimer','retirer la mention j’aime',"retirer la mention j'aime",'liked','aimé'];
          const likeNames = ['like',"j’aime","j'aime",'aimer'];
          const likedButton = buttons.find(e=>e.getAttribute('data-testid')==='unlike' || likedNames.includes(names(e)) || e.getAttribute('aria-pressed')==='true' && likeNames.includes(names(e)));
          const likeButton = buttons.find(e=>(e.getAttribute('data-testid')==='like' || likeNames.includes(names(e))) && e.getAttribute('aria-pressed')!=='true');
          const nextNames = behavior==='watchStories' ? ['next','suivant','next story','story suivante'] : ['next video','vidéo suivante','scroll down','faire défiler vers le bas'];
          const next = all(document,['button','[role=button]']).filter(visible).find(e=>nextNames.includes(names(e)));
          let scroller=item.parentElement;
          while (scroller && scroller!==document.body && scroller!==document.documentElement) {
            if (/(auto|scroll)/.test(getComputedStyle(scroller).overflowY) && scroller.scrollHeight>scroller.clientHeight+10) break;
            scroller=scroller.parentElement;
          }
          scroller=scroller && scroller!==document.body && scroller!==document.documentElement ? scroller : document.scrollingElement;
          const canScroll=!!scroller && scroller.scrollTop+scroller.clientHeight<scroller.scrollHeight-2;
          const result = {status:'ready',fingerprint,contentID,mediaPlaying:video ? !video.paused && video.readyState>=2 : null,liked:!!likedButton,canLike:!!likeButton && !!contentID,scrollOffset:scroller?.scrollTop ?? 0,canAdvance:!!next || behavior!=='watchStories' && canScroll,text:behavior==='readHeadlines' ? nodes.slice(0,5).map(e=>clean(e.innerText||e.textContent).slice(0,600)).filter(Boolean) : text ? [text] : []};
          if (command==='observe') return out(result);
          if (expected!==fingerprint) return out({status:'unavailable'});
          if (command==='play') {
            if (!video || !['watchVideos','watchStories'].includes(behavior)) return out({status:'unavailable'});
            video.play().catch(()=>{}); return out({status:'dispatched'});
          }
          if (command==='like') {
            if (!\#(likesAllowed && WebMorningBehavior.permitsLikes(for: site, behavior: behavior)) || !contentID || !likeButton || likedButton || ['news','whatsapp','gmail'].includes(site)) return out({status:'unavailable'});
            likeButton.click(); return out({status:'dispatched'});
          }
          if (command!=='advance') return out({status:'unavailable'});
          if (next && ['watchVideos','watchStories'].includes(behavior)) { next.click(); return out({status:'dispatched'}); }
          if (behavior==='watchStories') return out({status:'unavailable'});
          if (!canScroll) return out({status:'empty'});
          scroller.scrollBy({top:Math.max(200,scroller.clientHeight*0.85),behavior:'instant'});
          return out({status:'dispatched'});
        })()
        """#
    }

    private static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}
