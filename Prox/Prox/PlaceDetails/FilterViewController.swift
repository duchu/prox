/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

protocol FilterViewControllerDelegate: class {
    func filterViewController(_ filterViewController: FilterViewController, didUpdateFilters enabledFilters: [Bool], topRatedOnly: Bool)
    func filterViewController(_ filterViewController: FilterViewController, didDismissWithFilters enabledFilters: [Bool], topRatedOnly: Bool)
}

/// A drop-down view from the top of the screen that displays a list of categories to filter.
class FilterViewController: UIViewController {
    weak var delegate: FilterViewControllerDelegate?

    fileprivate var showFilterConstraints = [NSLayoutConstraint]()
    fileprivate var hideFilterConstraints = [NSLayoutConstraint]()

    fileprivate let background = UIButton()
    private let stackView = UIStackView()
    private let filters: [PlaceFilter]
    private(set) var enabledFilters: [Bool]
    private let placeCountLabel = UILabel()
    private let topRatedSwitch = UISwitch()

    init(filters: [PlaceFilter], enabledFilters: [Bool], topRatedOnly: Bool) {
        self.filters = filters
        self.enabledFilters = enabledFilters
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overCurrentContext
        transitioningDelegate = self

        topRatedSwitch.isOn = topRatedOnly
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        background.backgroundColor = Colors.filterOverlayDim
        background.alpha = 0
        background.addTarget(self, action: #selector(didPressClose), for: .touchDown)
        view.addSubview(background)

        let container = UIView()
        container.backgroundColor = .white
        view.addSubview(container)

        placeCountLabel.font = Fonts.filterPlaceCountLabel
        container.addSubview(placeCountLabel)

        let closeButton = UIButton()
        closeButton.setImage(#imageLiteral(resourceName: "button_dismiss"), for: .normal)
        closeButton.addTarget(self, action: #selector(didPressClose), for: .touchUpInside)
        view.addSubview(closeButton)

        for (i, filter) in filters.enumerated() {
            let button = FilterButton()
            button.setTitle(filter.label, for: .normal)
            button.isSelected = enabledFilters[i]
            button.tag = i
            button.addTarget(self, action: #selector(didToggleFilter(sender:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

        let topRated = UIView()
        topRated.backgroundColor = Colors.filterTopRatedBackground
        topRatedSwitch.onTintColor = Colors.filterButtonCheckedBackground
        topRatedSwitch.addTarget(self, action: #selector(didToggleRatings), for: .valueChanged)
        topRated.addSubview(topRatedSwitch)
        let ratingLabel = UILabel()
        ratingLabel.text = Strings.filterView.topRatedLabel
        ratingLabel.font = Fonts.filterTopRatedLabel
        ratingLabel.textColor = Colors.filterTopRatedLabel
        topRated.addSubview(ratingLabel)
        stackView.addArrangedSubview(topRated)

        let spacing: CGFloat = 16
        stackView.axis = .vertical
        stackView.spacing = spacing
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        container.addSubview(stackView)

        showFilterConstraints += [
            container.topAnchor.constraint(equalTo: view.topAnchor),
            placeCountLabel.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: spacing),
        ]

        hideFilterConstraints += [
            container.bottomAnchor.constraint(equalTo: view.topAnchor),
        ]

        let constraints = [
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),

            placeCountLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            closeButton.centerYAnchor.constraint(equalTo: placeCountLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -spacing),

            ratingLabel.leadingAnchor.constraint(equalTo: topRated.leadingAnchor, constant: spacing),
            ratingLabel.topAnchor.constraint(equalTo: topRated.topAnchor, constant: spacing),
            ratingLabel.bottomAnchor.constraint(equalTo: topRated.bottomAnchor, constant: -spacing),

            topRatedSwitch.trailingAnchor.constraint(equalTo: topRated.trailingAnchor, constant: -spacing),
            topRatedSwitch.topAnchor.constraint(equalTo: topRated.topAnchor, constant: spacing),
            topRatedSwitch.bottomAnchor.constraint(equalTo: topRated.bottomAnchor, constant: -spacing),

            topRated.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topRated.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: placeCountLabel.bottomAnchor, constant: spacing),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ]

        NSLayoutConstraint.activate(constraints + hideFilterConstraints, translatesAutoresizingMaskIntoConstraints: false)
    }

    var placeCount: Int = 0 {
        didSet {
            placeCountLabel.text = String(format: Strings.filterView.placeCount, placeCount)
        }
    }

    @objc private func didToggleFilter(sender: FilterButton) {
        let enabled = !enabledFilters[sender.tag]
        enabledFilters[sender.tag] = enabled
        sender.isSelected = enabled
        delegate?.filterViewController(self, didUpdateFilters: enabledFilters, topRatedOnly: topRatedSwitch.isOn)
    }

    @objc private func didPressClose() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func didToggleRatings() {
        delegate?.filterViewController(self, didUpdateFilters: enabledFilters, topRatedOnly: topRatedSwitch.isOn)
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag, completion: completion)
        delegate?.filterViewController(self, didDismissWithFilters: enabledFilters, topRatedOnly: topRatedSwitch.isOn)
    }
}

extension FilterViewController: UIViewControllerAnimatedTransitioning, UIViewControllerTransitioningDelegate {
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        transitionContext.containerView.addSubview(view)
        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            if transitionContext.viewController(forKey: .to) == self {
                self.background.alpha = 1
                NSLayoutConstraint.deactivate(self.hideFilterConstraints)
                NSLayoutConstraint.activate(self.showFilterConstraints, translatesAutoresizingMaskIntoConstraints: false)
            } else {
                self.background.alpha = 0
                NSLayoutConstraint.deactivate(self.showFilterConstraints)
                NSLayoutConstraint.activate(self.hideFilterConstraints, translatesAutoresizingMaskIntoConstraints: false)
            }

            self.view.layoutIfNeeded()
        }, completion: { _ in
            transitionContext.completeTransition(true)
        })
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.2
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self
    }
}

fileprivate class FilterButton: InsetButton {
    private static let checkedImage = #imageLiteral(resourceName: "icon_selected")
    private static let uncheckedImage = #imageLiteral(resourceName: "icon_add")

    override init() {
        super.init()

        titleLabel?.font = Fonts.filterButtonLabel
        contentEdgeInsets = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 16)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        layer.borderWidth = 1
        layer.borderColor = Colors.filterButtonBorder.cgColor
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate override var isSelected: Bool {
        didSet {
            super.isSelected = isSelected
            if isSelected {
                setTitleColor(Colors.filterButtonCheckedForeground, for: .normal)
                setImage(FilterButton.checkedImage, for: .normal)
                backgroundColor = Colors.filterButtonCheckedBackground
            } else {
                setTitleColor(Colors.filterButtonUncheckedForeground, for: .normal)
                setImage(FilterButton.uncheckedImage, for: .normal)
                backgroundColor = Colors.filterButtonUncheckedBackground
            }
        }
    }

    fileprivate override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.height / 2
    }
}
