// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

// swiftlint:disable sorted_imports
import Foundation
import UIKit

// swiftlint:disable superfluous_disable_command
// swiftlint:disable file_length implicit_return

// MARK: - Storyboard Scenes

// swiftlint:disable explicit_type_interface identifier_name line_length type_body_length type_name
internal enum StoryboardScene {
  internal enum About: StoryboardType {
    internal static let storyboardName = "About"

    internal static let initialScene = InitialSceneType<UIKit.UINavigationController>(storyboard: About.self)
  }
  internal enum Main: StoryboardType {
    internal static let storyboardName = "Main"

    internal static let initialScene = InitialSceneType<UIKit.UISplitViewController>(storyboard: Main.self)

    internal static let accountIdentifier = SceneType<AccountViewController>(storyboard: Main.self, identifier: "AccountIdentifier")

    internal static let configurationIdentifier = SceneType<ConfigurationViewController>(storyboard: Main.self, identifier: "ConfigurationIdentifier")

    internal static let providerPoolViewController = SceneType<ProviderPoolViewController>(storyboard: Main.self, identifier: "ProviderPoolViewController")

    internal static let serverNetworkViewController = SceneType<ServerNetworkViewController>(storyboard: Main.self, identifier: "ServerNetworkViewController")

    internal static let serviceIdentifier = SceneType<UIKit.UINavigationController>(storyboard: Main.self, identifier: "ServiceIdentifier")
  }
  internal enum Organizer: StoryboardType {
    internal static let storyboardName = "Organizer"

    internal static let initialScene = InitialSceneType<UIKit.UINavigationController>(storyboard: Organizer.self)

    internal static let provider = SceneType<UIKit.UINavigationController>(storyboard: Organizer.self, identifier: "Provider")

    internal static let wizardHostIdentifier = SceneType<UIKit.UINavigationController>(storyboard: Organizer.self, identifier: "WizardHostIdentifier")
  }
  internal enum Purchase: StoryboardType {
    internal static let storyboardName = "Purchase"

    internal static let initialScene = InitialSceneType<UIKit.UINavigationController>(storyboard: Purchase.self)
  }
  internal enum Shortcuts: StoryboardType {
    internal static let storyboardName = "Shortcuts"

    internal static let initialScene = InitialSceneType<UIKit.UINavigationController>(storyboard: Shortcuts.self)

    internal static let shortcutsViewController = SceneType<UIKit.UINavigationController>(storyboard: Shortcuts.self, identifier: "ShortcutsViewController")
  }
}
// swiftlint:enable explicit_type_interface identifier_name line_length type_body_length type_name

// MARK: - Implementation Details

internal protocol StoryboardType {
  static var storyboardName: String { get }
}

internal extension StoryboardType {
  static var storyboard: UIStoryboard {
    let name = self.storyboardName
    return UIStoryboard(name: name, bundle: BundleToken.bundle)
  }
}

internal struct SceneType<T: UIViewController> {
  internal let storyboard: StoryboardType.Type
  internal let identifier: String

  internal func instantiate() -> T {
    let identifier = self.identifier
    guard let controller = storyboard.storyboard.instantiateViewController(withIdentifier: identifier) as? T else {
      fatalError("ViewController '\(identifier)' is not of the expected class \(T.self).")
    }
    return controller
  }

  @available(iOS 13.0, tvOS 13.0, *)
  internal func instantiate(creator block: @escaping (NSCoder) -> T?) -> T {
    return storyboard.storyboard.instantiateViewController(identifier: identifier, creator: block)
  }
}

internal struct InitialSceneType<T: UIViewController> {
  internal let storyboard: StoryboardType.Type

  internal func instantiate() -> T {
    guard let controller = storyboard.storyboard.instantiateInitialViewController() as? T else {
      fatalError("ViewController is not of the expected class \(T.self).")
    }
    return controller
  }

  @available(iOS 13.0, tvOS 13.0, *)
  internal func instantiate(creator block: @escaping (NSCoder) -> T?) -> T {
    guard let controller = storyboard.storyboard.instantiateInitialViewController(creator: block) else {
      fatalError("Storyboard \(storyboard.storyboardName) does not have an initial scene.")
    }
    return controller
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
