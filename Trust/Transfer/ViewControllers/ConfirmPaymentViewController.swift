// Copyright SIX DAY LLC. All rights reserved.

import BigInt
import Foundation
import UIKit
import StackViewController
import Result
import StatefulViewController

enum ConfirmType {
    case sign
    case signThenSend
}

enum ConfirmResult {
    case signedTransaction(SentTransaction)
    case sentTransaction(SentTransaction)
}

class ConfirmPaymentViewController: UIViewController {

    private let keystore: Keystore
    let session: WalletSession
    let stackViewController = StackViewController()
    lazy var sendTransactionCoordinator = {
        return SendTransactionCoordinator(session: self.session, keystore: keystore, confirmType: confirmType)
    }()
    lazy var submitButton: UIButton = {
        let button = Button(size: .large, style: .solid)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(viewModel.actionButtonText, for: .normal)
        button.addTarget(self, action: #selector(send), for: .touchUpInside)
        return button
    }()
    lazy var viewModel: ConfirmPaymentViewModel = {
        return ConfirmPaymentViewModel(type: self.confirmType)
    }()
    var configurator: TransactionConfigurator
    let confirmType: ConfirmType
    var didCompleted: ((Result<ConfirmResult, AnyError>) -> Void)?

    init(
        session: WalletSession,
        keystore: Keystore,
        configurator: TransactionConfigurator,
        confirmType: ConfirmType
    ) {
        self.session = session
        self.keystore = keystore
        self.configurator = configurator
        self.confirmType = confirmType

        super.init(nibName: nil, bundle: nil)

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: R.image.settings_icon(), style: .plain, target: self, action: #selector(edit))
        view.backgroundColor = viewModel.backgroundColor
        stackViewController.view.backgroundColor = viewModel.backgroundColor
        navigationItem.title = viewModel.title

        errorView = ErrorView(onRetry: { [weak self] in
            self?.fetch()
        })

        fetch()
    }

    func fetch() {
        startLoading()
        configurator.load { [weak self] result in
            guard let `self` = self else { return }
            switch result {
            case .success:
                self.reloadView()
                self.endLoading()
            case .failure(let error):
                self.endLoading(animated: true, error: error, completion: nil)
            }
        }
        configurator.configurationUpdate.subscribe { [weak self] _ in
            guard let `self` = self else { return }
            self.reloadView()
        }
    }

    func configure(for detailsViewModel: ConfirmPaymentDetailsViewModel) {
        stackViewController.items.forEach { stackViewController.removeItem($0) }

        let header = TransactionHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.amountLabel.text = detailsViewModel.amountString
        header.amountLabel.font = detailsViewModel.amountFont
        header.amountLabel.textColor = detailsViewModel.amountTextColor

        var items: [UIView] = [
            .spacer(),
            header,
            TransactionAppearance.divider(color: Colors.lightGray, alpha: 0.3),
            TransactionAppearance.item(
                title: detailsViewModel.paymentFromTitle,
                subTitle: session.account.address.description
            ),
            TransactionAppearance.item(
                title: detailsViewModel.paymentToTitle,
                subTitle: detailsViewModel.paymentToText
            ),
            TransactionAppearance.item(
                title: detailsViewModel.gasLimitTitle,
                subTitle: detailsViewModel.gasLimitText
            ) { [unowned self] _, _, _ in
                self.edit()
            },
            TransactionAppearance.item(
                title: detailsViewModel.gasPriceTitle,
                subTitle: detailsViewModel.gasPriceText
            ) { [unowned self] _, _, _ in
                self.edit()
            },
            TransactionAppearance.item(
                title: detailsViewModel.feeTitle,
                subTitle: detailsViewModel.feeText
            ) { [unowned self] _, _, _ in
                self.edit()
            },
        ]

        // show total ether
        if case TransferType.ether(_) = configurator.transaction.transferType {
            items.append(TransactionAppearance.item(
                title: detailsViewModel.totalTitle,
                subTitle: detailsViewModel.totalText
            ))
        }

        for item in items {
            stackViewController.addItem(item)
        }

        stackViewController.scrollView.alwaysBounceVertical = true
        stackViewController.stackView.spacing = 10
        stackViewController.view.addSubview(submitButton)

        NSLayoutConstraint.activate([
            submitButton.bottomAnchor.constraint(equalTo: stackViewController.view.layoutGuide.bottomAnchor, constant: -15),
            submitButton.trailingAnchor.constraint(equalTo: stackViewController.view.trailingAnchor, constant: -15),
            submitButton.leadingAnchor.constraint(equalTo: stackViewController.view.leadingAnchor, constant: 15),
        ])

        displayChildViewController(viewController: stackViewController)
        updateSubmitButton()
    }

    private func updateSubmitButton() {
        let status = configurator.balanceValidStatus()
        let buttonTitle = viewModel.getActionButtonText(status, config: configurator.session.config, transferType: configurator.transaction.transferType)
        submitButton.isEnabled = status.sufficient
        submitButton.setTitle(buttonTitle, for: .normal)
    }

    private func reloadView() {
        let viewModel = ConfirmPaymentDetailsViewModel(
            transaction: configurator.previewTransaction(),
            currentBalance: session.balance,
            currencyRate: session.balanceCoordinator.currencyRate
        )
        self.configure(for: viewModel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func edit() {
        let controller = ConfigureTransactionViewController(
            configuration: configurator.configuration,
            transferType: configurator.transaction.transferType,
            config: session.config,
            currencyRate: session.balanceCoordinator.currencyRate
        )
        controller.delegate = self
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @objc func send() {
        self.displayLoading()

        let transaction = configurator.signTransaction()
        self.sendTransactionCoordinator.send(transaction: transaction) { [weak self] result in
            guard let `self` = self else { return }
            self.didCompleted?(result)
            self.hideLoading()
        }
    }
}

extension ConfirmPaymentViewController: StatefulViewController {
    func hasContent() -> Bool {
        return true
    }
}

extension ConfirmPaymentViewController: ConfigureTransactionViewControllerDelegate {
    func didEdit(configuration: TransactionConfiguration, in viewController: ConfigureTransactionViewController) {
        configurator.update(configuration: configuration)
        reloadView()
        navigationController?.popViewController(animated: true)
    }
}
