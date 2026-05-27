//
//  EmergencyContactView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

// MARK: - Reducer

@Reducer
struct EmergencyContactFeature {
  @Dependency(\.apis) var apis

  @ObservableState
  struct State: Equatable {
    let config: Config
    let emergencyContactData: EmergencyContactData

    var name: String = ""
    var relationship: String = ""
    var phone: String = ""

    var isSubmitting = false

    @Presents var alert: AlertState<Action.Alert>?

    var canSubmit: Bool {
      !name.trimmingCharacters(in: .whitespaces).isEmpty &&
      !relationship.trimmingCharacters(in: .whitespaces).isEmpty &&
      !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  enum Action: Equatable {
    case cancel
    case nameChanged(String)
    case relationshipChanged(String)
    case phoneChanged(String)
    case confirmTapped
    case confirmResult(TaskResult<Bool>)
    case alert(PresentationAction<Alert>)

    enum Alert: Equatable {}
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {

      case .cancel:
        return .none  // handled by parent

      case .nameChanged(let value):
        state.name = value
        return .none

      case .relationshipChanged(let value):
        state.relationship = value
        return .none

      case .phoneChanged(let value):
        state.phone = value
        return .none

      case .confirmTapped:
        guard state.canSubmit else {
          state.alert = AlertState {
            TextState("All Fields Required")
          } message: {
            TextState("Please fill in the contact's name, relationship, and phone number.")
          }
          return .none
        }

        state.isSubmitting = true

        let config = state.config
        let orderReference = state.emergencyContactData.orderReference
        let replyTopic = state.emergencyContactData.replyTopic
        let name = state.name.trimmingCharacters(in: .whitespaces)
        let relationship = state.relationship.trimmingCharacters(in: .whitespaces)
        let phone = state.phone.trimmingCharacters(in: .whitespaces)

        return .run { send in
          do {
            try await apis.publishEmergencyContactSaved(config, orderReference, name, relationship, phone, replyTopic)
            await send(.confirmResult(.success(true)))
          } catch {
            await send(.confirmResult(.failure(error)))
          }
        }

      case .confirmResult(.success):
        state.isSubmitting = false
        return .none  // parent dismisses

      case .confirmResult(.failure(let error)):
        state.isSubmitting = false
        state.alert = AlertState {
          TextState("Submission Failed")
        } message: {
          TextState(error.localizedDescription)
        }
        return .none

      case .alert:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }
}

// MARK: - EmergencyContactView

struct EmergencyContactView: View {
  @Bindable var store: StoreOf<EmergencyContactFeature>

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Full Name", text: Binding(
            get: { store.name },
            set: { store.send(.nameChanged($0)) }
          ))
          .textContentType(.oneTimeCode)
          .autocorrectionDisabled()

          TextField("Relationship", text: Binding(
            get: { store.relationship },
            set: { store.send(.relationshipChanged($0)) }
          ))
          .textContentType(.oneTimeCode)
          .autocorrectionDisabled()

          TextField("Phone Number", text: Binding(
            get: { store.phone },
            set: { store.send(.phoneChanged($0)) }
          ))
          .textContentType(.oneTimeCode)
          .keyboardType(.phonePad)
        } header: {
          Text("Emergency Contact")
        } footer: {
          Text("This information will be kept on file for the duration of the event.")
        }
      }
      .navigationTitle("Emergency Contact")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            store.send(.cancel)
          }
          .disabled(store.isSubmitting)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Confirm") {
            store.send(.confirmTapped)
          }
          .disabled(!store.canSubmit || store.isSubmitting)
        }
      }
      .alert($store.scope(state: \.alert, action: \.alert))
    }
  }
}
