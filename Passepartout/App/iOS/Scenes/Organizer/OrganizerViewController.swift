//
//  OrganizerViewController.swift
//  Passepartout
//
//  Created by Davide De Rosa on 9/2/18.
//  Copyright (c) 2021 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import StoreKit
import MessageUI
import SystemConfiguration.CaptiveNetwork
import PassepartoutConstants
import PassepartoutCore
import TunnelKitCore
import TunnelKitManager
import TunnelKitOpenVPN
import Convenience
import ConvenienceUI

// XXX: convoluted due to the separation of provider/host profiles

class OrganizerViewController: UITableViewController, StrongTableHost {
    private let service = TransientStore.shared.service
    
    private var providers: [String] = []

    private var hosts: [String] = []
    
    private var didShowSubreddit = false
    
    private var importer: HostImporter?
    
    private var hostParsingResult: OpenVPN.ConfigurationParser.Result?

    // MARK: StrongTableHost

    let model: StrongTableModel<SectionType, RowType> = StrongTableModel()
    
    func reloadModel() {
        model.clear()
        model.add(.vpn)
        model.add(.providers)
        model.add(.hosts)
        if #available(iOS 12, *) {
            model.add(.siri)
        }
        model.add(.support)
        model.add(.about)
        model.add(.destruction)
        model.setHeader(L10n.Service.Sections.Vpn.header, forSection: .vpn)
        model.setHeader(L10n.Organizer.Sections.Providers.header, forSection: .providers)
        model.setHeader(L10n.Organizer.Sections.Hosts.header, forSection: .hosts)
        model.setFooter(L10n.Organizer.Sections.Providers.footer, forSection: .providers)
        model.setFooter(L10n.Organizer.Sections.Hosts.footer, forSection: .hosts)
        if #available(iOS 12, *) {
            model.setHeader(L10n.Organizer.Sections.Siri.header, forSection: .siri)
            model.setFooter(L10n.Organizer.Sections.Siri.footer, forSection: .siri)
            model.set([.siriShortcuts], forSection: .siri)
        }
        model.setHeader(L10n.Organizer.Sections.Support.header, forSection: .support)
        model.set([.connectionStatus], forSection: .vpn)
        if ProductManager.shared.isEligibleForFeedback() {
            model.set([.donate, .joinCommunity, .writeReview], forSection: .support)
        } else {
            model.set([.donate, .joinCommunity], forSection: .support)
        }

        model.set([.openAbout], forSection: .about)
        model.set([.uninstall], forSection: .destruction)
        if ProductManager.shared.isBeta {
            model.add(.test)
            model.setHeader("Beta", forSection: .test)
            model.set([.testInterfaces, .testDisplayLog, .testTermination], forSection: .test)
        }
        
        //

        providers = service.sortedProviderNames()
        hosts = service.sortedHostIds()
        
        var providerRows = [RowType](repeating: .profile, count: providers.count)
        var hostRows = [RowType](repeating: .profile, count: hosts.count)
        providerRows.append(.addProvider)
        hostRows.append(.addHost)
        hostRows.append(.importHost)
        
        model.set(providerRows, forSection: .providers)
        model.set(hostRows, forSection: .hosts)
    }
    
    // MARK: UIViewController
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = GroupConstants.App.title
        navigationItem.rightBarButtonItem = editButtonItem
        Cells.destructive.register(with: tableView)
        reloadModel()
        tableView.reloadData()

        // XXX: if split vc is collapsed when a profile is in use, this vc
        // is not loaded on app launch. consequentially, service.delegate remains
        // nil until the Organizer is entered
        //
        // see UISplitViewControllerDelegate in AppDelegate (collapse is now commented out)
        service.delegate = self

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(vpnDidUpdate), name: VPN.didChangeStatus, object: nil)
        nc.addObserver(self, selector: #selector(productManagerDidReloadReceipt), name: ProductManager.didReloadReceipt, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !didShowSubreddit && !TransientStore.didHandleSubreddit {
            didShowSubreddit = true

            let alert = UIAlertController.asAlert(L10n.Reddit.title, L10n.Reddit.message)
            alert.addPreferredAction(L10n.Reddit.Buttons.subscribe) {
                TransientStore.didHandleSubreddit = true
                self.subscribeSubreddit()
            }
            alert.addAction(L10n.Reddit.Buttons.never) {
                TransientStore.didHandleSubreddit = true
            }
            alert.addCancelAction(L10n.Reddit.Buttons.remind)
            present(alert, animated: true, completion: nil)
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if let cell = sender as? UITableViewCell, let indexPath = tableView.indexPath(for: cell) {
            return model.row(at: indexPath) == .profile
        }

        // fall back to active profile if no selection
        return service.hasActiveProfile()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let destination = (segue.destination as? UINavigationController)?.topViewController

        if let vc = destination as? ServiceViewController {
            var selectedProfile: ConnectionProfile?

            // XXX: sender can be a cell or a profile
            selectedProfile = sender as? ConnectionProfile
            if selectedProfile == nil, let cell = sender as? UITableViewCell, let indexPath = tableView.indexPath(for: cell) {
                selectedProfile = profile(at: indexPath)
            }
            guard selectedProfile != nil else {
                assertionFailure("No selected profile")
                return
            }

            vc.setProfile(selectedProfile)
        } else if let vc = destination as? ImportedHostsViewController {
            vc.delegate = self
        } else if let vc = destination as? WizardHostViewController {
            vc.parsingResult = hostParsingResult
        }
    }

    // MARK: Actions
    
    private func enterProfile(_ profile: ConnectionProfile) {
        perform(segue: StoryboardSegue.Organizer.selectProfileSegueIdentifier, sender: profile)
    }

    private func enterActiveProfile() {
        guard let activeProfile = service.activeProfile else {
            return
        }
        enterProfile(activeProfile)
    }
    
    private func addNewProvider() {
        guard service.hasAvailableProviders() else {
            let alert = UIAlertController.asAlert(
                L10n.Organizer.Sections.Providers.header,
                L10n.Organizer.Alerts.ExhaustedProviders.message
            )
            alert.addCancelAction(L10n.Global.ok)
            present(alert, animated: true, completion: nil)
            return
        }
        perform(segue: StoryboardSegue.Organizer.addProviderSegueIdentifier)
    }

    private func addNewHost() {
        let picker = UIDocumentPickerViewController(documentTypes: AppConstants.URLs.filetypes, in: .import)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }
    
    private func tryParseHostURL(_ url: URL) {
        importer = HostImporter(withConfigurationURL: url, parentViewController: self)
        importer?.importHost(withPassphrase: nil, removeOnError: false, removeOnCancel: false) {
            self.hostParsingResult = $0
            self.perform(segue: StoryboardSegue.Organizer.importHostSegueIdentifier)
        }
    }

    private func importNewHost() {
        perform(segue: StoryboardSegue.Organizer.showImportedHostsSegueIdentifier)
    }
    
    private func addShortcuts() {
        do {
            try ProductManager.shared.verifyEligible(forFeature: .siriShortcuts)
        } catch ProductError.beta {
            presentBetaFeatureUnavailable("Siri")
            return
        } catch {
            presentPurchaseScreen(forProduct: .siriShortcuts)
            return
        }
        perform(segue: StoryboardSegue.Organizer.siriShortcutsSegueIdentifier)
    }

    private func donateToDeveloper() {
        guard SKPaymentQueue.canMakePayments() else {
            let alert = UIAlertController.asAlert(
                L10n.Organizer.Cells.Donate.caption,
                L10n.Organizer.Alerts.CannotDonate.message
            )
            alert.addCancelAction(L10n.Global.ok)
            present(alert, animated: true, completion: nil)
            return
        }
        perform(segue: StoryboardSegue.Organizer.donateSegueIdentifier, sender: nil)
    }

    private func offerTranslation() {
        let V = AppConstants.Translations.Email.self
        let recipient = V.recipient
        let subject = V.subject
        let body = V.body(V.template)
        
        guard MFMailComposeViewController.canSendMail() else {
            let app = UIApplication.shared
            guard let url = URL.mailto(to: recipient, subject: subject, body: body), app.canOpenURL(url) else {
                let alert = UIAlertController.asAlert(L10n.Translations.title, L10n.Global.emailNotConfigured)
                alert.addCancelAction(L10n.Global.ok)
                present(alert, animated: true, completion: nil)
                return
            }
            app.open(url, options: [:], completionHandler: nil)
            return
        }

        let vc = MFMailComposeViewController()
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = self
        vc.apply(.current)
        present(vc, animated: true, completion: nil)
    }
    
    private func about() {
        perform(segue: StoryboardSegue.Organizer.aboutSegueIdentifier, sender: nil)
    }
    
    private func removeProfile(at indexPath: IndexPath) {
        let sectionObject = model.section(forIndex: indexPath.section)
        let rowProfile = profileKey(at: indexPath)
        switch sectionObject {
        case .providers:
            providers.remove(at: indexPath.row)
            
        case .hosts:
            hosts.remove(at: indexPath.row)
            
        default:
            return
        }
        
//        var fallbackSection: SectionType?
        
        let total = providers.count + hosts.count
        
        // removed all profiles
        if total == 0 {
            VPN.shared.disconnect(completionHandler: nil)
        }
        // removed active profile
        else if service.isActiveProfile(rowProfile) {
//            let anyProvider = providerProfiles.first
//            let anyHost = hostProfiles.first
//            guard let anyProfile: ConnectionProfile = firstProvider ?? firstHost else {
//                fatalError("There must be one profile somewhere")
//            }
//            fallbackSection = (anyProvider != nil) ? .providers : .hosts
//            store.service.activateProfile(only)
            VPN.shared.disconnect(completionHandler: nil)
        }
        
        tableView.beginUpdates()
        model.deleteRow(at: indexPath.row, ofSection: sectionObject)
        tableView.deleteRows(at: [indexPath], with: .automatic)
//        if let fallbackSection = fallbackSection {
//            let section = model.index(ofSection: fallbackSection)
//            tableView.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
//        }
        tableView.endUpdates()
        
        service.removeProfile(rowProfile)
        if #available(iOS 12, *) {
            IntentDispatcher.forgetProfile(withKey: rowProfile)
        }
    }

    private func confirmVpnProfileDeletion() {
        let alert = UIAlertController.asAlert(
            L10n.Organizer.Cells.Uninstall.caption,
            L10n.Organizer.Alerts.DeleteVpnProfile.message
        )
        alert.addPreferredAction(L10n.Global.ok) {
            VPN.shared.uninstall(completionHandler: nil)
        }
        alert.addCancelAction(L10n.Global.cancel)
        present(alert, animated: true, completion: nil)
    }
    
    private func becomeSponsor() {
        UIApplication.shared.open(AppConstants.URLs.githubSponsors, options: [:], completionHandler: nil)
    }
    
    private func subscribeSubreddit() {
        UIApplication.shared.open(AppConstants.URLs.subreddit, options: [:], completionHandler: nil)
    }
    
    private func writeReview() {
        let url = Reviewer.urlForReview(withAppId: AppConstants.App.appStoreId)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    //
    
    private func testInterfaces() {
        let alert = UIAlertController.asAlert("Test interfaces", nil)
        alert.addCancelAction(L10n.Global.ok)
        defer {
            present(alert, animated: true, completion: nil)
        }
        guard let interfaceNames = CNCopySupportedInterfaces() as? [CFString] else {
            alert.message = "Nil result from CNCopySupportedInterfaces()"
            return
        }

        var message = interfaceNames.description
        message += "\n\n"
        for name in interfaceNames {
            message += name as String
            message += "\n"
            guard let iface = CNCopyCurrentNetworkInfo(name) else {
                continue
            }
            message += (iface as NSDictionary).description
            message += "\n"
        }
        alert.message = message
    }
    
    private func testDisplayLog() {
        guard let log = try? String(contentsOf: AppConstants.Log.fileURL) else {
            return
        }
        let alert = UIAlertController.asAlert("Debug log", log)
        alert.addCancelAction(L10n.Global.ok)
        present(alert, animated: true, completion: nil)
    }
    
    private func testTermination() {
        exit(0)
    }
    
    // MARK: Notifications

    @objc private func vpnDidUpdate() {
        tableView.reloadData()
    }
    
    @objc private func productManagerDidReloadReceipt() {
        reloadModel()
        tableView.reloadData()
    }
}

// MARK: -

extension OrganizerViewController {
    enum SectionType: Int {
        case vpn
        
        case providers
        
        case hosts
        
        case siri
        
        case support
        
        case about
        
        case destruction

        case test
    }
    
    enum RowType: Int {
        case connectionStatus
        
        case profile
        
        case addProvider
        
        case addHost
        
        case importHost
        
        case siriShortcuts
        
        case donate
        
        case githubSponsors
        
        case translate
        
        case joinCommunity
        
        case writeReview
        
        case openAbout
        
        case uninstall
        
        case testInterfaces
        
        case testDisplayLog

        case testTermination
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return model.numberOfSections
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return model.header(forSection: section)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return model.footer(forSection: section)
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return model.headerHeight(for: section)
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return model.footerHeight(for: section)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.numberOfRows(forSection: section)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch model.row(at: indexPath) {
        case .connectionStatus:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.applyVPN(.current, with: VPN.shared.isEnabled ? VPN.shared.status : nil, error: nil)
            cell.leftText = L10n.Service.Cells.ConnectionStatus.caption
            return cell

        case .profile:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            let rowProfile = profileKey(at: indexPath)
            if rowProfile.context == .provider {
                let metadata = InfrastructureFactory.shared.metadata(forName: rowProfile.id)
                cell.imageView?.image = metadata?.logo
            } else {
                cell.imageView?.image = nil
            }
            cell.leftText = service.screenTitle(rowProfile)
            cell.rightText = service.isActiveProfile(rowProfile) ? L10n.Organizer.Cells.Profile.Value.current : nil
            return cell

        case .addProvider:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.applyAction(.current)
            cell.leftText = L10n.Organizer.Cells.AddProvider.caption
            return cell

        case .addHost:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.applyAction(.current)
            cell.leftText = L10n.Organizer.Cells.AddHost.caption
            return cell
            
        case .importHost:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.applyAction(.current)
            cell.leftText = L10n.Organizer.Cells.ImportHost.caption
            return cell

        case .siriShortcuts:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.applyAction(.current)
            cell.leftText = L10n.Organizer.Cells.SiriShortcuts.caption
            return cell
            
        case .donate:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = L10n.Organizer.Cells.Donate.caption
            return cell

        case .githubSponsors:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = L10n.Organizer.Cells.GithubSponsors.caption
            return cell
            
        case .translate:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = L10n.Organizer.Cells.Translate.caption
            return cell
            
        case .joinCommunity:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = L10n.Organizer.Cells.JoinCommunity.caption
            return cell
            
        case .writeReview:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = L10n.Organizer.Cells.WriteReview.caption
            return cell
            
        case .openAbout:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = L10n.Organizer.Cells.About.caption(GroupConstants.App.name)
            cell.rightText = ApplicationInfo.appVersion
            return cell
            
        case .uninstall:
            let cell = Cells.destructive.dequeue(from: tableView, for: indexPath)
            cell.caption = L10n.Organizer.Cells.Uninstall.caption
            return cell
            
        case .testInterfaces:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = "Show interfaces"
            return cell

        case .testDisplayLog:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = "Display current log"
            return cell

        case .testTermination:
            let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
            cell.leftText = "Terminate app"
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch model.row(at: indexPath) {
        case .connectionStatus:
            enterActiveProfile()
            
        case .profile:
            enterProfile(profile(at: indexPath))
            
        case .addProvider:
            addNewProvider()

        case .addHost:
            addNewHost()
            
        case .importHost:
            importNewHost()
            
        case .siriShortcuts:
            addShortcuts()
            
        case .donate:
            donateToDeveloper()

        case .githubSponsors:
            becomeSponsor()
            
        case .translate:
            offerTranslation()
            
        case .joinCommunity:
            subscribeSubreddit()
            
        case .writeReview:
            writeReview()
            
        case .openAbout:
            about()
            
        case .uninstall:
            confirmVpnProfileDeletion()
            
        case .testInterfaces:
            testInterfaces()
            
        case .testDisplayLog:
            testDisplayLog()
            
        case .testTermination:
            testTermination()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard tableView.isEditing else {
            return false
        }
        return model.row(at: indexPath) == .profile
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        removeProfile(at: indexPath)
    }
    
    // MARK: Helpers
    
    private func sectionProfiles(at indexPath: IndexPath) -> [String] {
        let ids: [String]
        let sectionObject = model.section(forIndex: indexPath.section)
        switch sectionObject {
        case .providers:
            ids = providers
            
        case .hosts:
            ids = hosts
            
        default:
            fatalError("Unexpected section: \(sectionObject)")
        }
        guard indexPath.row < ids.count else {
            fatalError("No profile found at \(indexPath), is it an add cell?")
        }
        return ids
    }
    
    private func profileKey(at indexPath: IndexPath) -> ProfileKey {
        let section = model.section(forIndex: indexPath.section)
        switch section {
        case .providers:
            return ProfileKey(.provider, providers[indexPath.row])
            
        case .hosts:
            return ProfileKey(.host, hosts[indexPath.row])
            
        default:
            fatalError("Profile found in unexpected section: \(section)")
        }
    }

    private func profile(at indexPath: IndexPath) -> ConnectionProfile {
        let id = sectionProfiles(at: indexPath)[indexPath.row]
        let section = model.section(forIndex: indexPath.section)
        let context: Context
        switch section {
        case .providers:
            context = .provider
            
        case .hosts:
            context = .host
            
        default:
            fatalError("Profile found in unexpected section: \(section)")
        }
        guard let found = service.profile(withContext: context, id: id) else {
            fatalError("Profile (\(context), \(id)) could not be found, why was it returned?")
        }
        return found
    }
}

// MARK: -

extension OrganizerViewController: ConnectionServiceDelegate {
    func connectionService(didAdd profile: ConnectionProfile) {
        TransientStore.shared.serialize(withProfiles: false) // add
        
        reloadModel()
        tableView.reloadData()

        if #available(iOS 12, *) {
            IntentDispatcher.donateEnableVPN()
        }

        // XXX: hack around bad replace when detail presented in compact view
        if let detailNav = navigationController?.viewControllers.last as? UINavigationController {
            var existingServiceVC: ServiceViewController?
            for vc in detailNav.viewControllers {
                if let found = vc as? ServiceViewController {
                    existingServiceVC = found
                    break
                }
            }
            let serviceVC = existingServiceVC ?? (StoryboardScene.Main.serviceIdentifier.instantiate().topViewController as! ServiceViewController)
            serviceVC.setProfile(profile)
            detailNav.setViewControllers([serviceVC], animated: true)
            return
        }
        perform(segue: StoryboardSegue.Organizer.selectProfileSegueIdentifier, sender: profile)
    }
    
    func connectionService(didRename profile: ConnectionProfile, to newTitle: String) {
        TransientStore.shared.serialize(withProfiles: false) // rename

        reloadModel()
        tableView.reloadData()
    }
    
    func connectionService(didRemoveProfileWithKey key: ProfileKey) {
        TransientStore.shared.serialize(withProfiles: false) // delete

        splitViewController?.serviceViewController?.hideProfileIfDeleted()
    }
    
    // XXX: deactivate + activate leads to a redundant serialization
    
    func connectionService(willDeactivate profile: ConnectionProfile) {
        TransientStore.shared.serialize(withProfiles: false) // deactivate

        tableView.reloadData()
    }
    
    func connectionService(didActivate profile: ConnectionProfile) {
        TransientStore.shared.serialize(withProfiles: false) // activate

        tableView.reloadData()

        if #available(iOS 12, *) {
            IntentDispatcher.donateEnableVPN()
        }
    }
    
    func connectionService(didUpdate profile: ConnectionProfile) {
    }
}

extension OrganizerViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        tryParseHostURL(url)
    }
}

extension OrganizerViewController: ImportedHostsViewControllerDelegate {
    func importedHostsController(_: ImportedHostsViewController, didImport url: URL) {
        dismiss(animated: true) {
            self.tryParseHostURL(url)
        }
    }
}

extension OrganizerViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)
    }
}
