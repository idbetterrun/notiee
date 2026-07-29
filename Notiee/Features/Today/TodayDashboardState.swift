import Foundation

/// The single most important thing Today should show right now.
///
/// Priority (highest first) is decided by `TodayContextResolver`:
/// 1. `.activeEvent` — a scheduled event happening right now.
/// 2. `.dueTodo` — an incomplete todo overdue or due within two hours.
/// 3. `.imminentEvent` — a scheduled event starting within 30 minutes.
/// 4. `.recordMomentum` — three or more records captured today.
/// 5. `.calm` — nothing urgent; invite the user to record.
enum TodayHero: Equatable {
    case activeEvent(ScheduledEvent)
    case dueTodo(NoteTodo)
    case imminentEvent(ScheduledEvent)
    case recordMomentum(count: Int)
    case calm
}

/// The adaptive "what else" slot below the Hero and urgent items.
///
/// An execution Hero (`.activeEvent`, `.dueTodo`, `.imminentEvent`) pairs with `.todos`
/// (actionable items to keep working through). A reflection/calm Hero (`.recordMomentum`,
/// `.calm`) pairs with `.records` (recent capture history).
enum TodayReviewSlot: Equatable {
    case todos([NoteTodo])
    case records([NoteRecord])
}

/// Deterministic, bounded snapshot of "what matters right now" for the Today 2.0
/// Context Dashboard. Produced by `TodayContextResolver.resolve`; purely a function of
/// its inputs, no side effects, no network.
struct TodayDashboardState: Equatable {
    let hero: TodayHero
    /// Up to two overdue/due-soon todos not already shown as the Hero.
    let urgentTodos: [NoteTodo]
    /// Up to two imminent events not already shown as the Hero.
    let urgentEvents: [ScheduledEvent]
    let review: TodayReviewSlot
    let todayRecordCount: Int
    let actionableTodoCount: Int
}
