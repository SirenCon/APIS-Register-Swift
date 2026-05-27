//
//  RegSetupConfigView.swift
//  Register
//

import CodeScanner
import ComposableArchitecture
import SwiftUI
import os

@Reducer
struct RegSetupConfigFeature {
  @Dependency(\.config) var config
  @Dependency(\.apis) var apis

  @ObservableState
  struct State: Equatable {
    var isPresentingScanner = false
    var preferFrontCamera = UIDevice.current.userInterfaceIdiom == .pad
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case showScanner(Bool)
    case scannerResult(TaskResult<String>)
    case clear
    case closeApp
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none
      case .showScanner(let shouldShow):
        state.isPresentingScanner = shouldShow
        return .none
      case .scannerResult:
        state.isPresentingScanner = false
        return .none
      case .clear:
        return .run { _ in
          try? await config.clear()
        }
      case .closeApp:
        exit(0)
      }
    }
  }
}

struct RegSetupConfigView: View {
  @Bindable var store: StoreOf<RegSetupConfigFeature>

  var body: some View {
    Section("Terminal Registration") {
      Button {
        store.send(.showScanner(true))
      } label: {
        Label("Scan Config QR Code", systemImage: "qrcode.viewfinder")
      }

      Toggle(isOn: $store.preferFrontCamera) {
        Label(
          "Prefer Front Camera",
          systemImage: "arrow.trianglehead.2.clockwise.rotate.90.camera"
        )
      }

      Button(role: .destructive) {
        store.send(.clear)
      } label: {
        Label("Clear Terminal Registration", systemImage: "trash")
          .foregroundColor(.red)
      }

      Button(role: .destructive) {
        store.send(.closeApp)
      } label: {
        Label("Close App", systemImage: "ant.fill")
          .foregroundStyle(Color.red)
      }
    }
  }
}

struct RegSetupConfigView_Previews: PreviewProvider {
  static var previews: some View {
    Form {
      RegSetupConfigView(
        store: Store(initialState: .init()) {
          RegSetupConfigFeature()
        }
      )
    }
    .previewLayout(.fixed(width: 400, height: 400))
  }
}
