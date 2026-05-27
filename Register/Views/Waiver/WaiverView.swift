//
//  WaiverView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

// MARK: - Reducer

@Reducer
struct WaiverFeature {
  @Dependency(\.apis) var apis

  @ObservableState
  struct State: Equatable {
    let config: Config
    let waiverData: WaiverData

    /// Paths drawn by the user in the signature box.
    var signaturePaths: [Path] = []
    /// The last point from the active drag gesture.
    var currentDragPoint: CGPoint? = nil

    var isSubmitting = false
    var emailCopy = true

    @Presents var alert: AlertState<Action.Alert>?
  }

  enum Action: Equatable {
    case cancel
    case clearSignature
    case dragChanged(startPoint: CGPoint, location: CGPoint)
    case dragEnded
    case setEmailCopy(Bool)
    case submitTapped
    case submitResult(TaskResult<Bool>)
    case alert(PresentationAction<Alert>)

    enum Alert: Equatable {}
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {

      case .cancel:
        return .none  // handled by parent

      case .clearSignature:
        state.signaturePaths = []
        state.currentDragPoint = nil
        return .none

      case let .setEmailCopy(value):
        state.emailCopy = value
        return .none

      case let .dragChanged(startPoint, location):
        if state.currentDragPoint == nil {
          // Start a new sub-path from startPoint to location
          var path = Path()
          path.move(to: startPoint)
          path.addLine(to: location)
          state.signaturePaths.append(path)
        } else {
          // Extend the last path
          guard !state.signaturePaths.isEmpty else { return .none }
          let idx = state.signaturePaths.count - 1
          state.signaturePaths[idx].addLine(to: location)
        }
        state.currentDragPoint = location
        return .none

      case .dragEnded:
        state.currentDragPoint = nil
        return .none

      case .submitTapped:
        guard !state.signaturePaths.isEmpty else {
          state.alert = AlertState {
            TextState("Signature Required")
          } message: {
            TextState("Please sign in the signature box before accepting.")
          }
          return .none
        }

        state.isSubmitting = true

        let config = state.config
        let orderReference = state.waiverData.orderReference
        let replyTopic = state.waiverData.replyTopic
        let paths = state.signaturePaths
        let emailCopy = state.emailCopy

        return .run { send in
          do {
            let signatureBase64 = renderSignatureToPngBase64(paths: paths, size: CGSize(width: 600, height: 150))
            try await apis.publishWaiverSigned(config, orderReference, signatureBase64, replyTopic, emailCopy)
            await send(.submitResult(.success(true)))
          } catch {
            await send(.submitResult(.failure(error)))
          }
        }

      case .submitResult(.success):
        state.isSubmitting = false
        return .none  // parent dismisses

      case .submitResult(.failure(let error)):
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

// MARK: - Signature rendering helper

/// Renders the captured signature paths into a PNG and returns them as a base64 string.
private func renderSignatureToPngBase64(paths: [Path], size: CGSize) -> String {
  let renderer = UIGraphicsImageRenderer(size: size)
  let image = renderer.image { ctx in
    UIColor.white.setFill()
    ctx.fill(CGRect(origin: .zero, size: size))

    UIColor.black.setStroke()
    let cgContext = ctx.cgContext
    cgContext.setLineWidth(2.5)
    cgContext.setLineCap(.round)
    cgContext.setLineJoin(.round)

    for path in paths {
      let cgPath = path.cgPath
      cgContext.addPath(cgPath)
      cgContext.strokePath()
    }
  }
  return image.pngData()?.base64EncodedString() ?? ""
}

// MARK: - Signature Canvas

/// A fixed-size drawing canvas that captures finger/stylus strokes as Paths.
struct SignatureCanvas: View {
  @Binding var paths: [Path]
  var onDragChanged: (CGPoint, CGPoint) -> Void
  var onDragEnded: () -> Void

  /// Tracks where the current drag gesture started so we can append correctly.
  @State private var dragStart: CGPoint = .zero

  var body: some View {
    Canvas { context, _ in
      for path in paths {
        var stroke = path
        context.stroke(stroke, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
      }
    }
    .background(Color.white)
    .border(Color.gray, width: 1)
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
          if value.translation == .zero {
            dragStart = value.location
          }
          onDragChanged(dragStart, value.location)
          dragStart = value.location
        }
        .onEnded { _ in
          onDragEnded()
        }
    )
    // Prevent the parent scroll view from stealing this gesture
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in }
    )
  }
}

// MARK: - WaiverView

struct WaiverView: View {
  @Bindable var store: StoreOf<WaiverFeature>

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          waiverBody
          signatureSection
        }
        .padding()
      }
      // Prevent the scroll view from intercepting gestures inside the canvas
      .scrollDisabled(false)
      .navigationTitle("Release of Liability")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            store.send(.cancel)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Accept") {
            store.send(.submitTapped)
          }
          .disabled(store.isSubmitting)
        }
      }
      .alert(store: store.scope(state: \.$alert, action: \.alert))
      .overlay {
        if store.isSubmitting {
          ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("Submitting…")
              .padding()
              .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 12))
          }
        }
      }
    }
    .preferredColorScheme(.light)
  }

  // MARK: Waiver text body

  @ViewBuilder
  var waiverBody: some View {
    let d = store.waiverData

    Text("RELEASE OF LIABILITY")
      .font(.headline)
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)

    Text("READ CAREFULLY – THIS AFFECTS YOUR LEGAL RIGHTS")
      .font(.subheadline)
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)

    Text("""
In exchange for participation in the activity of SirenCon organized by SirenCon™ and the Samoset Council of Scouting America, of 5403 Spider Lake Rd., Rhinelander, Wisconsin, 54501 and/or use of the property, facilities and services of SirenCon™ and the Samoset Council of Scouting America, I,
""")

    waiverField(label: "Name", value: d.name)

    HStack(spacing: 12) {
      waiverField(label: "Address", value: d.address)
    }

    HStack(spacing: 12) {
      waiverField(label: "City", value: d.city)
      waiverField(label: "State", value: d.state)
      waiverField(label: "ZIP", value: d.zipcode)
    }

    Text("agree for myself and (if applicable) for the members of my family, to the following:")

    waiverParagraph(number: "1", title: "AGREEMENT TO FOLLOW DIRECTIONS.", body: "I agree to observe and obey all posted rules and warnings, and further agree to follow any oral instructions or directions given by SirenCon™ and the Samoset Council of Scouting America, or the employees, representatives or agents of SirenCon™ and the Samoset Council of Scouting America.")

    waiverParagraph(number: "2", title: "ASSUMPTION OF THE RISKS AND RELEASE.", body: "I recognize that there are certain inherent risks associated with the above described activity and I assume full responsibility for personal injury to myself and (if applicable) my family members, and further release and discharge SirenCon™ and the Samoset Council of Scouting America for injury, loss or damage arising out of my family's use of or presence upon the facilities of SirenCon™ and the Samoset Council of Scouting America, whether caused by the fault of myself, my family, SirenCon™ and the Samoset Council of Scouting America or other third parties.")

    waiverParagraph(number: "3", title: "INDEMNIFICATION.", body: "I agree to indemnify and defend SirenCon™ and the Samoset Council of Scouting America against all claims, causes of action, damages, judgements, costs, or expenses, including attorney fees and other litigation costs, which may in any way arise from my or my family's use of or presence upon the facilities of SirenCon™ and the Samoset Council of Scouting America.")

    waiverParagraph(number: "4", title: "FEES.", body: "I agree to pay for all damages to the facilities of SirenCon™ and the Samoset Council of Scouting America caused by any negligent, reckless, or willful actions by me or my family.")

    waiverParagraph(number: "5", title: "APPLICABLE LAW.", body: "Any legal or equitable claim that may arise from the participation in the above shall be resolved under Wisconsin law.")

    waiverParagraph(number: "6", title: "NO DURESS.", body: "I agree and acknowledge that I am under no pressure or duress to sign this Agreement and that I have been given a reasonable opportunity to review it before signing. I further agree and acknowledge that I am free to have my own legal counsel review this Agreement if I so desire. I further agree and acknowledge that SirenCon™ and the Samoset Council of Scouting America has offered to refund any fees I have paid to use the facilities if I choose not to sign this Agreement.")

    waiverParagraph(number: "7", title: "ARM\u{2019}S LENGTH AGREEMENT.", body: "This Agreement and each of its terms are the product of an arm\u{2019}s length negotiation between the Parties. In the event any ambiguity is found to exist in the interpretation of this Agreement, or any of its provisions, the Parties, and each of them, explicitly reject the application of any legal or equitable rule of interpretation which would lead to a construction either \u{201C}for\u{201D} or \u{201C}against\u{201D} a particular party based upon their status as the drafter of a specific term, language, or provision giving rise to such ambiguity.")

    waiverParagraph(number: "8", title: "ENFORCEABILITY.", body: "The invalidity or unenforceability of any provision of this Agreement, whether standing alone or as applied to a particular occurrence or circumstance, shall not affect the validity or enforceability of any other provision of this Agreement or any other applications of such provision, as the case may be, and such invalid or unenforceable provision shall be deemed not to be a part of the Agreement.")

    Group {
      Text("9. ").bold() + Text("EMERGENCY CONTACT. ").bold() + Text("In case of an emergency, please call:")
    }

    HStack(spacing: 12) {
      waiverField(label: "Emergency Contact Name", value: d.emergencyContactName.isEmpty ? "—" : d.emergencyContactName)
      waiverField(label: "Relationship", value: d.emergencyContactRelationship.isEmpty ? "—" : d.emergencyContactRelationship)
      waiverField(label: "Phone", value: d.emergencyContactPhone.isEmpty ? "—" : d.emergencyContactPhone)
    }

    Text("I HAVE READ THIS DOCUMENT AND UNDERSTAND IT. I FURTHER UNDERSTAND THAT BY SIGNING THIS RELEASE, I VOLUNTARILY SURRENDER CERTAIN LEGAL RIGHTS.")
      .bold()
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.top, 8)
  }

  // MARK: Signature section

  @ViewBuilder
  var signatureSection: some View {
    Divider()

    Text("Signature")
      .font(.headline)

    // The canvas is in a fixed-height container so the ScrollView cannot
    // intercept the drawing gestures. We display store.signaturePaths via a
    // Binding.constant (read-only for display) and route all mutations through
    // store actions.
    SignatureCanvas(
      paths: Binding.constant(store.signaturePaths),
      onDragChanged: { start, loc in
        store.send(.dragChanged(startPoint: start, location: loc))
      },
      onDragEnded: {
        store.send(.dragEnded)
      }
    )
    .frame(height: 150)
    .contentShape(Rectangle())

    HStack {
      Button(role: .destructive) {
        store.send(.clearSignature)
      } label: {
        Label("Clear Signature", systemImage: "trash")
      }
      .buttonStyle(.bordered)

      Spacer()

      HStack {
        Text("Date:").foregroundStyle(.secondary)
        Text(store.waiverData.date).bold()
      }
    }

    Toggle(
      "Email me a copy of this waiver",
      isOn: $store.emailCopy.sending(\.setEmailCopy)
    )
    .padding(.bottom, 8)
  }

  // MARK: Helpers

  @ViewBuilder
  func waiverField(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value.isEmpty ? " " : value)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
          Divider()
        }
    }
  }

  @ViewBuilder
  func waiverParagraph(number: String, title: String, body: String) -> some View {
    (Text("\(number). ").bold() + Text(title).bold() + Text(" ") + Text(body))
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Previews

#Preview {
  WaiverView(
    store: Store(
      initialState: WaiverFeature.State(
        config: .mock,
        waiverData: .mock
      )
    ) {
      WaiverFeature()
    }
  )
}
