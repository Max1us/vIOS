//
//  TransactionsTableViewController.swift
//  VergeiOS
//
//  Created by Swen van Zanten on 31-07-18.
//  Copyright © 2018 Verge Currency. All rights reserved.
//

import UIKit

class TransactionsTableViewController: EdgedTableViewController {

    let addressBookManager = AddressBookManager()

    var transactions: [[Transaction]] = []
    var dates: [Date] = []
    let searchController = UISearchController(searchResultsController: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        DispatchQueue.main.async {
            self.tableView.reloadData()
        }

        if searchController.isActive {
            TorStatusIndicator.shared.hide()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        TorStatusIndicator.shared.show()
    }

    func setupView() {
        if !WalletManager.default.hasTransactions() {
            if let placeholder = Bundle.main.loadNibNamed("NoTransactionsPlaceholderView", owner: self, options: nil)?.first as? NoTransactionsPlaceholderView {
                placeholder.frame = tableView.frame
                tableView.backgroundView = placeholder
                tableView.backgroundView?.backgroundColor = .backgroundGrey()
                tableView.tableFooterView = UIView()
                navigationItem.searchController = nil
            }
            return
        }

        // Setup the Search Controller
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Transactions"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        edgesForExtendedLayout = UIRectEdge.all
        extendedLayoutIncludesOpaqueBars = true

        // Setup the Scope Bar
        searchController.searchBar.scopeButtonTitles = ["All", "Sent", "Received"]
        searchController.searchBar.delegate = self
        searchController.delegate = self

        loadTransactions()
    }

    func loadTransactions(_ searchText: String = "", scope: String = "All") {
        transactions.removeAll()
        dates.removeAll()

        let categories = [
            "Sent": TransactionType.Sent,
            "Received": TransactionType.Received
        ]

        let ftransactions = WalletManager.default.getTransactions().filter { transaction in
            let doesCategoryMatch = (scope == "All") || (transaction.category == categories[scope])

            if searchText == "" {
                return doesCategoryMatch
            }

            return doesCategoryMatch && (
                transaction.address.lowercased().contains(searchText.lowercased())
                || transaction.amount.description.lowercased().contains(searchText.lowercased())
                || transaction.account.lowercased().contains(searchText.lowercased())
            )
        }

        let cal = Calendar.current
        let items = Dictionary(grouping: ftransactions, by: { cal.startOfDay(for: $0.time) }).sorted(
            by: { $0.key > $1.key }
        )

        for item in items {
            dates.append(item.key)
            transactions.append(item.value.sorted { thule, thule2 in
                return thule.time.timeIntervalSinceReferenceDate > thule2.time.timeIntervalSinceReferenceDate
            })
        }
    }
    
    func sectionDate(bySection section: Int) -> Date {
        return dates[section]
    }
    
    func transactions(bySection section: Int) -> [Transaction] {
        return transactions[section]
    }
    
    func transaction(byIndexpath indexPath: IndexPath) -> Transaction {
        let items = transactions(bySection: indexPath.section)
        
        return items[indexPath.row]
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return transactions.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60.0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions(bySection: section).count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = Bundle.main.loadNibNamed("TransactionTableViewCell", owner: self, options: nil)?.first as! TransactionTableViewCell
        
        let item = transaction(byIndexpath: indexPath)

        var recipient: Address? = nil
        if let name = addressBookManager.name(byAddress: item.address) {
            recipient = Address()
            recipient?.address = item.address
            recipient?.name = name
        }

        cell.setTransaction(item, address: recipient)
        cell.backgroundColor = .backgroundGrey()
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performSegue(withIdentifier: "TransactionTableViewController", sender: self)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        
        return df.string(from: sectionDate(bySection: section))
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = UIColor.secondaryDark()
        header.textLabel?.font = UIFont.avenir(size: 14).demiBold()
        header.textLabel?.frame = header.frame
        header.textLabel?.text = header.textLabel?.text?.capitalized
    }
    

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "TransactionTableViewController" {
            if let vc = segue.destination as? TransactionTableViewController {
                vc.navigationItem.leftBarButtonItem = nil
                vc.transaction = transaction(byIndexpath: tableView.indexPathForSelectedRow!)
            }
        }
    }

}

extension TransactionsTableViewController: UISearchBarDelegate {
    // MARK: - UISearchBar Delegate
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        loadTransactions(searchBar.text!, scope: searchBar.scopeButtonTitles![selectedScope])
        tableView.reloadData()
    }
}

extension TransactionsTableViewController: UISearchResultsUpdating, UISearchControllerDelegate {
    // MARK: - UISearchResultsUpdating Delegate
    func updateSearchResults(for searchController: UISearchController) {
        let searchBar = searchController.searchBar
        let scope = searchBar.scopeButtonTitles![searchBar.selectedScopeButtonIndex]

        loadTransactions(searchBar.text!, scope: scope)
        tableView.reloadData()
    }

    public func willPresentSearchController(_ searchController: UISearchController) {
        TorStatusIndicator.shared.hide()
    }

    public func willDismissSearchController(_ searchController: UISearchController) {
        TorStatusIndicator.shared.show()

        searchController.searchBar.selectedScopeButtonIndex = 0
    }
}