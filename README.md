# Cancellation via CancelID enum with associated value no longer works as expected since TCA 1.20.2

## Description

In our real-world project, we have several legacy services that recently migrated their internal implementation to use a `Store`, without changing the public interface. In certain situations, these services are used concurrently by multiple clients, and therefore long-running effects must be cancelled with awareness of which client initiated them.

To reproduce the issue, I’ve created a minimal demo project. When tapping the `Start` button, a timer effect begins, updating a count on screen every second. When tapping `End`, the effect should cancel.

However, in TCA version `1.20.2`, canceling an effect with an enum-based CancelID that contains an associated UUID does not work as expected. You can try checking out the `tca-1.11` branch in the sample project, where this behavior works correctly.

## Deeper investigation

I looked into `Cancellation.swift` and noticed that all `AnyCancellable` instances are stored in a `CancellablesCollection`, keyed by `_CancelID`, which conforms to `Hashable`.

However, even when using the same key to cancel an effect, the cancellation doesn’t happen. Breakpoint debugging reveals that the expected AnyCancellable isn’t found when calling .cancel(id:).

## Question

I suspect this may be related to how `Hashable` is implemented on CancelID enums with associated values. I’m unsure whether this pattern is no longer supported — though I recall seeing this usage pattern discussed in a past TCA thread (but I couldn’t find the reference again).

Is this usage considered valid?
If not, what would be the recommended approach for canceling effects based on dynamic IDs (like UUID)?

## Part of code

```swift
@Reducer
struct BatchServiceStore: Reducer {
    @ObservableState
    struct State: Equatable {
        struct Status: Equatable {
            let uuid: UUID
            let count: Int
        }
        
        var status: Status?
    }
    
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case start(UUID), end(UUID)
    }
    
    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce(core)
    }
    
    enum CancelID: Hashable { case longRun(UUID) } // 👈 Here, with associated value
    
    private func core(_ state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .start(uuid):
            return Observable
                .interval(.seconds(1), scheduler: MainScheduler.instance)
                .map {
                    BatchServiceStore.State.Status(uuid: uuid, count: $0)
                }
                .map { Action.binding(.set(\.status, $0)) }
                .toEffectAndSkipError()
                .cancellable(id: CancelID.longRun(uuid), cancelInFlight: true)
            
        case let .end(uuid):
            return .cancel(id: CancelID.longRun(uuid))
            
        case .binding:
            break
        }
        
        return .none
    }
}
```