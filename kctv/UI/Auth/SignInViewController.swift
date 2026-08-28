import AuthenticationServices
import UIKit

/// Giriş ekranı: Apple ile giriş, Google ile giriş, ya da misafir olarak devam.
final class SignInViewController: UIViewController {
    private let model: AppModel
    /// Apple isteğiyle birlikte üretilen ham nonce; yanıt gelene kadar saklanır.
    private var rawNonce: String?

    private let stack = UIStackView()
    private let errorLabel = UILabel()
    private let googleButton = UIButton(configuration: .bordered())
    private let guestButton = UIButton(type: .system)

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private let backdropLayer = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        addBackdrop()
        buildLayout()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authDidChange),
            name: .appModelAuthDidChange,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropLayer.frame = view.bounds
    }

    private func addBackdrop() {
        backdropLayer.colors = [
            UIColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1).cgColor,
            UIColor.black.cgColor,
        ]
        view.layer.insertSublayer(backdropLayer, at: 0)
    }

    private func buildLayout() {
        let icon = UIImageView(image: UIImage(systemName: "play.tv.fill"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = UILabel()
        title.text = "KCTV"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = L10n.appTagline
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = AppPalette.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let appleButton = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        appleButton.addTarget(self, action: #selector(startAppleSignIn), for: .primaryActionTriggered)
        appleButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        var googleConfiguration = UIButton.Configuration.bordered()
        googleConfiguration.title = L10n.signInWithGoogle
        googleConfiguration.image = UIImage(systemName: "g.circle.fill")
        googleConfiguration.imagePadding = 8
        googleConfiguration.baseForegroundColor = .white
        googleConfiguration.cornerStyle = .capsule
        googleButton.configuration = googleConfiguration
        googleButton.addTarget(self, action: #selector(startGoogleSignIn), for: .touchUpInside)
        googleButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = .systemOrange
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        [icon, title, subtitle, appleButton, googleButton, errorLabel].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(24, after: subtitle)
        view.addSubview(stack)

        guestButton.setTitle(L10n.continueAsGuest, for: .normal)
        guestButton.setTitleColor(AppPalette.secondaryText, for: .normal)
        guestButton.addTarget(self, action: #selector(continueAsGuest), for: .touchUpInside)
        guestButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guestButton)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),

            guestButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guestButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Aksiyonlar

    @objc private func startAppleSignIn() {
        let nonce = AppleNonce.random()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    @objc private func startGoogleSignIn() {
        Task { await model.signInWithGoogle() }
    }

    @objc private func continueAsGuest() {
        Task { await model.continueAsGuest() }
    }

    @objc private func authDidChange() {
        errorLabel.text = model.authError
        errorLabel.isHidden = model.authError == nil
        stack.alpha = model.isAuthenticating ? 0.5 : 1
        stack.isUserInteractionEnabled = !model.isAuthenticating
    }
}

extension SignInViewController: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { await model.handleAppleAuthorization(.success(authorization), rawNonce: rawNonce) }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        Task { await model.handleAppleAuthorization(.failure(error), rawNonce: rawNonce) }
    }
}

extension SignInViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = view.window {
            return window
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            if let keyWindow = activeScene.windows.first(where: \.isKeyWindow) {
                return keyWindow
            }
            if let anyWindow = activeScene.windows.first {
                return anyWindow
            }
            return UIWindow(windowScene: activeScene)
        }
        fatalError("No active window scene found for authentication presentation")
    }
}
