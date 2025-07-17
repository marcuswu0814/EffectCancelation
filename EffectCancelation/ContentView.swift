//
//  ContentView.swift
//  EffectCancelation
//
//  Created by Marcus Wu on 2025/7/17.
//

import Combine
import ComposableArchitecture
import Dependencies
import RxSwift
import RxCombine
import SwiftUI

@Reducer
struct ContentFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var uuid = UUID()
        var mutatingStatus: BatchServiceStore.State.Status?
    }
    
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task, newUUID, start, end
    }
    
    @Dependency(BatchService.self) var batchService
    
    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce(core)
    }
    
    private func core(_ state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .task:
            return batchService.status
                .map { Action.binding(.set(\.mutatingStatus, $0)) }
                .toEffectAndSkipError()
            
        case .start:
            batchService.start(state.uuid)
            
        case .end:
            batchService.end(state.uuid)
            
        case .newUUID:
            state.uuid = UUID()
            
        case .binding: break
        }
        
        return .none
    }
}

struct ContentView: View {
    @Bindable var store: StoreOf<ContentFeature>
    
    var body: some View {
        VStack {
            Text(store.mutatingStatus?.uuid.uuidString ?? "No UUID")
                .font(.title)
            
            Text(store.mutatingStatus?.count.description ?? "No Count")
                .font(.title2)
            
            HStack {
                Button("Start") {
                    store.send(.start)
                }
                
                Button("End") {
                    store.send(.end)
                }
                
                Button("New UUID") {
                    store.send(.newUUID)
                }
            }
        }
        .task { await store.send(.task).finish() }
        .padding()
    }
}

#Preview {
    ContentView(store: .init(initialState: .init()) {
        ContentFeature()
    })
}

// MARK: - A service that hidden implementation details

struct BatchService {
    let start: (UUID) -> Void
    let end: (UUID) -> Void
    let status: Observable<BatchServiceStore.State.Status>
}

extension BatchService: DependencyKey {
    static var liveValue: BatchService {
        let store: StoreOf<BatchServiceStore> = .init(initialState: .init()) {
            BatchServiceStore()
        }
        
        return .init(
            start: { uuid in
                store.send(.start(uuid))
            },
            end: { uuid in
                store.send(.end(uuid))
            },
            status: store
                .publisher
                .compactMap(\.status)
                .asObservable()
        )
    }
}

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
    
    enum CancelID: Hashable { case longRun(UUID) }
    
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

// MARK: - Extensions for Rx Observable to TCA Effect

extension ObservableConvertibleType {
    func toEffectAndSkipError() -> Effect<Element> {
        .publisher {
            publisher
                .catch { _ in Empty(completeImmediately: true) }
        }
    }

    func fireAndForget<NewOutput>(
        outputType: NewOutput.Type = NewOutput.self
    ) -> Effect<NewOutput> {
        .publisher {
            publisher
                .flatMap { _ in Empty<NewOutput, any Error>() }
                .catch { _ in Empty(completeImmediately: true) }
        }
    }
}
