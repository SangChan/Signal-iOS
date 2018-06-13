//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ConversationSearchViewController: UITableViewController {

    var searchResultSet: SearchResultSet = SearchResultSet.empty

    var uiDatabaseConnection: YapDatabaseConnection {
        // TODO do we want to respond to YapDBModified? Might be hard when there's lots of search results, for only marginal value
        return OWSPrimaryStorage.shared().uiDatabaseConnection
    }

    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    private var contactsManager: OWSContactsManager {
        return Environment.current().contactsManager
    }

    enum SearchSection: Int {
        case noResults
        case conversations
        case contacts
        case messages
    }

    var blockedPhoneNumberSet = Set<String>()

    // MARK: View Lifecyle

    override func viewDidLoad() {
        super.viewDidLoad()

        let blockingManager = OWSBlockingManager.shared()
        blockedPhoneNumberSet = Set(blockingManager.blockedPhoneNumbers())

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 60

        tableView.register(EmptySearchResultCell.self, forCellReuseIdentifier: EmptySearchResultCell.reuseIdentifier)
        tableView.register(HomeViewCell.self, forCellReuseIdentifier: HomeViewCell.cellReuseIdentifier())
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier())
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFail("\(logTag) unknown section selected.")
            return
        }

        switch searchSection {
        case .noResults:
            owsFail("\(logTag) shouldn't be able to tap 'no results' section")
        case .conversations:
            let sectionResults = searchResultSet.conversations
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFail("\(logTag) unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared().presentConversation(for: thread.threadRecord, action: .compose)

        case .contacts:
            let sectionResults = searchResultSet.contacts
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFail("\(logTag) unknown row selected.")
                return
            }

            SignalApp.shared().presentConversation(forRecipientId: searchResult.recipientId, action: .compose)

        case .messages:
            let sectionResults = searchResultSet.messages
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFail("\(logTag) unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared().presentConversation(for: thread.threadRecord,
                                                   action: .compose,
                                                   focusMessageId: searchResult.messageId)
        }
    }

    // MARK: UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFail("unknown section: \(section)")
            return 0
        }

        switch searchSection {
        case .noResults:
            return searchResultSet.isEmpty ? 1 : 0
        case .conversations:
            return searchResultSet.conversations.count
        case .contacts:
            return searchResultSet.contacts.count
        case .messages:
            return searchResultSet.messages.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch searchSection {
        case .noResults:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptySearchResultCell.reuseIdentifier) as? EmptySearchResultCell else {
                owsFail("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard indexPath.row == 0 else {
                owsFail("searchResult was unexpected index")
                return UITableViewCell()
            }

            let searchText = self.searchResultSet.searchText
            cell.configure(searchText: searchText)
            return cell
        case .conversations:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: HomeViewCell.cellReuseIdentifier()) as? HomeViewCell else {
                owsFail("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.conversations[safe: indexPath.row] else {
                owsFail("searchResult was unexpectedly nil")
                return UITableViewCell()
            }
            cell.configure(withThread: searchResult.thread, contactsManager: contactsManager, blockedPhoneNumber: self.blockedPhoneNumberSet)
            return cell
        case .contacts:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier()) as? ContactTableViewCell else {
                owsFail("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.contacts[safe: indexPath.row] else {
                owsFail("searchResult was unexpectedly nil")
                return UITableViewCell()
            }
            cell.configure(with: searchResult.signalAccount, contactsManager: contactsManager)
            return cell
        case .messages:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: HomeViewCell.cellReuseIdentifier()) as? HomeViewCell else {
                owsFail("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.messages[safe: indexPath.row] else {
                owsFail("searchResult was unexpectedly nil")
                return UITableViewCell()
            }

            var overrideSnippet = NSAttributedString()
            var overrideTimestamp: NSNumber?
            if let messageId = searchResult.messageId {
                if let messageTimestamp = searchResult.messageTimestamp {
                    overrideTimestamp = NSNumber(value: messageTimestamp)
                } else {
                    owsFail("\(ConversationSearchViewController.logTag) message search result is missing message timestamp")
                }

                // Note that we only use the snippet for message results,
                // not conversation results.  HomeViewCell will generate
                // a snippet for conversations that reflects the latest
                // contents.
                if let messageSnippet = searchResult.snippet {
                    // YDB uses bold tags to highlight matches within the snippet.
                    let filteredSnippet = messageSnippet
                        .replacingOccurrences(of: "<b>", with: "")
                        .replacingOccurrences(of: "</b>", with: "")
                        .replacingOccurrences(of: "<B>", with: "")
                        .replacingOccurrences(of: "</B>", with: "")

                    overrideSnippet = NSAttributedString(string: filteredSnippet)
                } else {
                    owsFail("\(ConversationSearchViewController.logTag) message search result is missing message snippet")
                }
            }

            cell.configure(withThread: searchResult.thread,
                           contactsManager: contactsManager,
                           blockedPhoneNumber: self.blockedPhoneNumberSet,
                overrideSnippet: overrideSnippet,
                overrideTimestamp: overrideTimestamp)

            return cell
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFail("unknown section: \(section)")
            return nil
        }

        switch searchSection {
        case .noResults:
            return nil
        case .conversations:
            if searchResultSet.conversations.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONVERSATIONS", comment: "section header for search results that match existing conversations (either group or contact conversations)")
            } else {
                return nil
            }
        case .contacts:
            if searchResultSet.contacts.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONTACTS", comment: "section header for search results that match a contact who doesn't have an existing conversation")
            } else {
                return nil
            }
        case .messages:
            if searchResultSet.messages.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_MESSAGES", comment: "section header for search results that match a message in a conversation")
            } else {
                return nil
            }
        }
    }

    // MARK: UISearchBarDelegate

    @objc
    public func updateSearchResults(searchText: String) {
        guard searchText.stripped.count > 0 else {
            self.searchResultSet = SearchResultSet.empty
            self.tableView.reloadData()
            return
        }

        // TODO: async?
        // TODO: debounce?

        self.uiDatabaseConnection.read { transaction in
            self.searchResultSet = self.searcher.results(searchText: searchText, transaction: transaction, contactsManager: self.contactsManager)
        }

        // TODO: more performant way to do this?
        self.tableView.reloadData()
    }
}

class EmptySearchResultCell: UITableViewCell {
    static let reuseIdentifier = "EmptySearchResultCell"

    let messageLabel: UILabel
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        self.messageLabel = UILabel()
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        messageLabel.font = UIFont.ows_dynamicTypeBody
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3

        contentView.addSubview(messageLabel)

        messageLabel.autoSetDimension(.height, toSize: 150)

        messageLabel.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        messageLabel.autoVCenterInSuperview()
        messageLabel.autoHCenterInSuperview()

        messageLabel.setContentHuggingHigh()
        messageLabel.setCompressionResistanceHigh()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(searchText: String) {
        let format = NSLocalizedString("HOME_VIEW_SEARCH_NO_RESULTS_FORMAT", comment: "Format string when search returns no results. Embeds {{search term}}")
        let messageText: String = NSString(format: format as NSString, searchText) as String
        self.messageLabel.text = messageText
    }
}
