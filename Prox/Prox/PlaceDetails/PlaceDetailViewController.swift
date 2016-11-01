/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import AFNetworking
import BadgeSwift

/**
 * This class has essentially implemented it's own version of a paging collection view

 * The reason we have done this and not used either a UIPageViewController or a UICollectionViewController is as follows
 * * UIPageViewController does not allow for pages with width < screen size, so there is no option to have the edges of previous
 *   and next view controllers showing at the same time as the current view controller
 * * UICollectionViewController will give us the previous, but will not allow us to specify custom paging transition animations
 *
 *  By rolling this view controller by hand we get both the layout we want AND the custom paging animation
 **/
class PlaceDetailViewController: UIViewController {

    weak var dataSource: PlaceDataSource? {
        didSet {
            mapButtonBadge.text = "\(dataSource?.numberOfPlaces() ?? 0)"
        }
    }

    lazy var imageDownloader: AFImageDownloader = {
        // TODO: Maybe we want more control over the configuration.
        let sessionManager = AFHTTPSessionManager(sessionConfiguration: .default)
        sessionManager.responseSerializer = AFImageResponseSerializer() // sets correct mime-type.

        let activeDownloadCount = 4 // TODO: value?
        let cache = AFAutoPurgingImageCache() // defaults 100 MB max -> 60 MB after purge
        return AFImageDownloader(sessionManager: sessionManager, downloadPrioritization: .FIFO,
                                 maximumActiveDownloads: activeDownloadCount, imageCache: cache)
    }()

    fileprivate lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.didPan(gestureRecognizer:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.minimumNumberOfTouches = 1
        return panGesture
    }()
    
    lazy var mapButton: MapButton = {
        let button = MapButton()
        button.setImage(UIImage(named: "icon_mapview"), for: .normal)
        button.addTarget(self, action: #selector(self.close), for: .touchUpInside)
        button.clipsToBounds = false
        return button
    }()

    lazy var mapButtonBadge: BadgeSwift = {
        let badge = BadgeSwift()
        badge.font = Fonts.detailsViewMapButtonBadgeText
        badge.badgeColor = Colors.detailsViewMapButtonBadgeBackground
        badge.textColor = Colors.detailsViewMapButtonBadgeFont
        badge.shadowOpacityBadge = 0.5
        badge.shadowOffsetBadge = CGSize(width: 0, height: 0)
        badge.shadowRadiusBadge = 1.0
        badge.shadowColorBadge = Colors.detailsViewMapButtonShadow
        return badge
    }()

    fileprivate var previousCardViewController: PlaceDetailsCardViewController?
    fileprivate var currentCardViewController: PlaceDetailsCardViewController
    fileprivate var nextCardViewController: PlaceDetailsCardViewController?
    fileprivate var unusedPlaceCardViewControllers = [PlaceDetailsCardViewController]()

    fileprivate var currentCardViewCenterXConstraint: NSLayoutConstraint?
    fileprivate var previousCardViewTrailingConstraint: NSLayoutConstraint?
    fileprivate var nextCardViewLeadingConstraint: NSLayoutConstraint?

    var imageCarousel: UIView!

    fileprivate let cardViewTopAnchorConstant: CGFloat = 204
    fileprivate let cardViewSpacingConstant: CGFloat = 6
    fileprivate let cardViewWidthConstant: CGFloat = 343
    fileprivate let imageCarouselHeightConstant: CGFloat = 240

    init(place: Place) {
        self.currentCardViewController = PlaceDetailsCardViewController(place: place)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(white: 0.5, alpha: 1) // TODO: blurred image background

        imageCarousel = currentCardViewController.imageCarousel
        view.addSubview(imageCarousel)
        var constraints = [imageCarousel.topAnchor.constraint(equalTo: view.topAnchor),
                           imageCarousel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                           imageCarousel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                           imageCarousel.heightAnchor.constraint(equalToConstant: imageCarouselHeightConstant)]

        view.addSubview(currentCardViewController.cardView)
        currentCardViewCenterXConstraint = currentCardViewController.cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        constraints += [currentCardViewController.cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: cardViewTopAnchorConstant),
                        currentCardViewController.cardView.widthAnchor.constraint(equalToConstant: cardViewWidthConstant),
                        currentCardViewCenterXConstraint!]
        self.addChildViewController(currentCardViewController)

        // add a pan gesture recognizer to the current place card
        currentCardViewController.cardView.addGestureRecognizer(panGestureRecognizer)


        if let previousPlace = dataSource?.previousPlace(forPlace: currentCardViewController.place) {
            previousCardViewController = dequeuePlaceCardViewController(forPlace: previousPlace)
            view.addSubview(previousCardViewController!.cardView)
            previousCardViewTrailingConstraint = previousCardViewController!.cardView.trailingAnchor.constraint(equalTo: currentCardViewController.cardView.leadingAnchor, constant: -cardViewSpacingConstant)
            constraints += [previousCardViewController!.cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: cardViewTopAnchorConstant),
                            previousCardViewController!.cardView.widthAnchor.constraint(equalToConstant: cardViewWidthConstant),
                            previousCardViewTrailingConstraint!]
        }

        if let nextPlace = dataSource?.nextPlace(forPlace: currentCardViewController.place) {
            nextCardViewController = dequeuePlaceCardViewController(forPlace: nextPlace)
            view.addSubview(nextCardViewController!.cardView)
            nextCardViewLeadingConstraint = nextCardViewController!.cardView.leadingAnchor.constraint(equalTo: currentCardViewController.cardView.trailingAnchor, constant: cardViewSpacingConstant)
            constraints += [nextCardViewController!.cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: cardViewTopAnchorConstant),
                            nextCardViewController!.cardView.widthAnchor.constraint(equalToConstant: cardViewWidthConstant),
                            nextCardViewLeadingConstraint!]
        }

        view.addSubview(mapButton)
        constraints += [mapButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 36),
                        mapButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                        mapButton.heightAnchor.constraint(equalToConstant: 48),
                        mapButton.widthAnchor.constraint(equalToConstant: 48)]

        view.addSubview(mapButtonBadge)
        constraints += [mapButtonBadge.leadingAnchor.constraint(equalTo: mapButton.trailingAnchor, constant: -10),
                        mapButtonBadge.topAnchor.constraint(equalTo: mapButton.topAnchor),
                        mapButtonBadge.heightAnchor.constraint(equalToConstant: 20.0),
                        mapButtonBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20.0)]


        NSLayoutConstraint.activate(constraints, translatesAutoresizingMaskIntoConstraints: false)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    fileprivate func dequeuePlaceCardViewController(forPlace place: Place) -> PlaceDetailsCardViewController {
        if let placeCardVC = unusedPlaceCardViewControllers.last {
            unusedPlaceCardViewControllers.removeLast()
            placeCardVC.place = place
            return placeCardVC
        }

        return PlaceDetailsCardViewController(place: place)
    }

    var startConstant: CGFloat!

    func didPan(gestureRecognizer: UIPanGestureRecognizer) {

        if gestureRecognizer.state == .began {
            startConstant = currentCardViewCenterXConstraint?.constant ?? 0
        }

        let translationX = gestureRecognizer.translation(in: self.view).x

        if gestureRecognizer.state == .ended {
            // figure out where the view would stop based on the velocity with which the user is panning
            // this is so that paging quickly feels natural
            let velocityX = (0.2 * gestureRecognizer.velocity(in: self.view).x)
            let finalX = startConstant + translationX + velocityX;
            let animationDuration = 0.5

            if canPageToNextPlaceCard(finalXPosition: finalX) {
                pageToNextPlaceCard(animateWithDuration: animationDuration)
            } else if canPageToPreviousPlaceCard(finalXPosition: finalX) {
                pageToPreviousPlaceCard(animateWithDuration: animationDuration)
            } else {
                unwindToCurrentPlaceCard(animateWithDuration: animationDuration)
            }
        } else {
            currentCardViewCenterXConstraint?.constant = startConstant + translationX
        }
    }

    fileprivate func canPageToNextPlaceCard(finalXPosition: CGFloat) -> Bool {
        return finalXPosition < -(self.view.frame.width * 0.5) && self.nextCardViewController != nil
    }

    fileprivate func pageToNextPlaceCard(animateWithDuration animationDuration: TimeInterval) {
        guard let nextCardViewController = nextCardViewController  else {
            return
        }
        // check to see if there is a next card to the next card
        // add a new view controller to next card view controller
        // if so, remove currentCardViewController centerX constraint
        // add center x constraint to nextCardViewController
        
        let nextCardImageCarousel = addImageCarousel(forNextCard: nextCardViewController)

        let newNextCardViewController = insertNewNextViewController(toNextCard: nextCardViewController)
        let springDamping:CGFloat = newNextCardViewController == nil ? 0.8 : 1.0

        previousCardViewController?.cardView.isHidden = true

        setupConstraints(forNewPreviousCard: currentCardViewController, toNewCurrentCard: nextCardViewController)

        view.layoutIfNeeded()

        // setup constraints for new central card
        if let currentCardViewCenterXConstraint = currentCardViewCenterXConstraint {
            NSLayoutConstraint.deactivate([currentCardViewCenterXConstraint])
        }

        self.currentCardViewCenterXConstraint = nextCardViewController.cardView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        NSLayoutConstraint.activate([self.currentCardViewCenterXConstraint!])

        // animate the constraint changes
        UIView.animate(withDuration: animationDuration, delay: 0.0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
            self.imageCarousel.alpha = 0
            nextCardImageCarousel.alpha = 1
            self.view.layoutIfNeeded()
        }, completion: { finished in
            if finished {
                // ensure that the correct current, previous and next view controller references are set
                self.imageCarousel.removeFromSuperview()
                self.imageCarousel = nextCardImageCarousel
                self.currentCardViewController.cardView.removeGestureRecognizer(self.panGestureRecognizer)
                if let previousCardViewController = self.previousCardViewController {
                    previousCardViewController.cardView.removeFromSuperview()
                    previousCardViewController.cardView.isHidden = false
                    previousCardViewController.removeFromParentViewController()
                    self.unusedPlaceCardViewControllers.append(previousCardViewController)
                }
                self.previousCardViewController = self.currentCardViewController
                self.currentCardViewController = nextCardViewController
                self.currentCardViewController.cardView.addGestureRecognizer(self.panGestureRecognizer)
                self.nextCardViewController = newNextCardViewController
            }
        })
    }

    fileprivate func insertNewNextViewController(toNextCard nextCardViewController: PlaceDetailsCardViewController) -> PlaceDetailsCardViewController? {
        // deactivate and remove next view controller leading constraint
        if let nextCardViewLeadingConstraint = nextCardViewLeadingConstraint {
            NSLayoutConstraint.deactivate([nextCardViewLeadingConstraint])
        }

        guard let newNext = dataSource?.nextPlace(forPlace: nextCardViewController.place) else {
            nextCardViewLeadingConstraint = nil
            return nil
        }

        let newNextCardViewController = dequeuePlaceCardViewController(forPlace:newNext)
        self.view.addSubview(newNextCardViewController.cardView)
        self.addChildViewController(newNextCardViewController)
        self.nextCardViewLeadingConstraint = newNextCardViewController.cardView.leadingAnchor.constraint(equalTo: nextCardViewController.cardView.trailingAnchor, constant: cardViewSpacingConstant)
        NSLayoutConstraint.activate([newNextCardViewController.cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: cardViewTopAnchorConstant),
                                  newNextCardViewController.cardView.widthAnchor.constraint(equalToConstant: cardViewWidthConstant),
                                  self.nextCardViewLeadingConstraint!], translatesAutoresizingMaskIntoConstraints: false)

        return newNextCardViewController
    }

    fileprivate func setupConstraints(forNewPreviousCard newPreviousCard: PlaceDetailsCardViewController, toNewCurrentCard newCurrentCard: PlaceDetailsCardViewController) {
        // setup constraints for new previous card
        if let previousCardViewTrailingConstraint = previousCardViewTrailingConstraint {
            NSLayoutConstraint.deactivate([previousCardViewTrailingConstraint])
        }
        self.previousCardViewTrailingConstraint = newPreviousCard.cardView.trailingAnchor.constraint(equalTo: newCurrentCard.cardView.leadingAnchor, constant: -cardViewSpacingConstant)
        NSLayoutConstraint.activate([self.previousCardViewTrailingConstraint!])
    }

    fileprivate func canPageToPreviousPlaceCard(finalXPosition: CGFloat) -> Bool {
        return finalXPosition > (self.view.frame.width * 0.5) && self.previousCardViewController != nil
    }

    // check to see if there is a previous card to the previous card
    // add a new view controller to previous card view controller
    // if so, remove currentCardViewController centerX constraint
    // add center x constraint to previousCardViewController
    fileprivate func pageToPreviousPlaceCard(animateWithDuration animationDuration: TimeInterval) {
        guard let previousCardViewController = previousCardViewController else {
            return
        }

        // add the image carousel for the previous place card underneath the existing carousel
        // we need to ensure these constraints are applied and rendered before we animate the rest, otherwise we end
        // up with a very odd looking fade transition
        let previousCardImageCarousel = addImageCarousel(forNextCard: previousCardViewController)

        nextCardViewController?.cardView.isHidden = true

        let newPreviousCardViewController = insertNewPreviousViewController(toPreviousCard: previousCardViewController)
        let springDamping:CGFloat = newPreviousCardViewController == nil ? 0.8 : 1.0
        setupConstraints(forNewNextCard: currentCardViewController, toNewCurrentCard: previousCardViewController)

        view.layoutIfNeeded()

        // deactivate and remove current view controller center constraint
        if let currentCardViewCenterXConstraint = currentCardViewCenterXConstraint {
            NSLayoutConstraint.deactivate([currentCardViewCenterXConstraint])
        }

        self.currentCardViewCenterXConstraint = previousCardViewController.cardView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        NSLayoutConstraint.activate([currentCardViewCenterXConstraint!])


        UIView.animate(withDuration: animationDuration, delay: 0.0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
            self.imageCarousel.alpha = 0
            previousCardImageCarousel.alpha = 1
            self.view.layoutIfNeeded()
            }, completion: { finished in
            if finished {
                self.currentCardViewController.cardView.removeGestureRecognizer(self.panGestureRecognizer)
                if let nextCardViewController = self.nextCardViewController {
                    nextCardViewController.cardView.removeFromSuperview()
                    nextCardViewController.cardView.isHidden = false
                    nextCardViewController.removeFromParentViewController()
                    self.unusedPlaceCardViewControllers.append(nextCardViewController)
                }
                self.imageCarousel.removeFromSuperview()
                self.imageCarousel = previousCardImageCarousel
                self.nextCardViewController = self.currentCardViewController
                self.currentCardViewController = previousCardViewController
                self.currentCardViewController.cardView.addGestureRecognizer(self.panGestureRecognizer)
                self.previousCardViewController = newPreviousCardViewController
            }
        })
    }


    fileprivate func insertNewPreviousViewController(toPreviousCard previousCardViewController: PlaceDetailsCardViewController) -> PlaceDetailsCardViewController? {
        // deactivate and remove previous view controller trailing constraint
        if let previousCardViewTrailingConstraint = previousCardViewTrailingConstraint {
            NSLayoutConstraint.deactivate([previousCardViewTrailingConstraint])
        }

        guard let newNext = dataSource?.previousPlace(forPlace: previousCardViewController.place) else {
            previousCardViewTrailingConstraint = nil
            return nil
        }

        let newPreviousCardViewController = dequeuePlaceCardViewController(forPlace:newNext)
        self.view.addSubview(newPreviousCardViewController.cardView)
        self.addChildViewController(newPreviousCardViewController)
        self.previousCardViewTrailingConstraint = newPreviousCardViewController.cardView.trailingAnchor.constraint(equalTo: previousCardViewController.cardView.leadingAnchor, constant: -cardViewSpacingConstant)
        NSLayoutConstraint.activate([newPreviousCardViewController.cardView.topAnchor.constraint(equalTo: view.topAnchor, constant: cardViewTopAnchorConstant),
                                     newPreviousCardViewController.cardView.widthAnchor.constraint(equalToConstant: cardViewWidthConstant),
                                     self.previousCardViewTrailingConstraint!], translatesAutoresizingMaskIntoConstraints: false)

        return newPreviousCardViewController
    }

    fileprivate func setupConstraints(forNewNextCard newNextCard: PlaceDetailsCardViewController, toNewCurrentCard newCurrentCard: PlaceDetailsCardViewController) {
        // setup constraints for new previous card
        if let nextCardViewLeadingConstraint = nextCardViewLeadingConstraint {
            NSLayoutConstraint.deactivate([nextCardViewLeadingConstraint])
        }
        self.nextCardViewLeadingConstraint = newNextCard.cardView.leadingAnchor.constraint(equalTo: newCurrentCard.cardView.trailingAnchor, constant: cardViewSpacingConstant)
        NSLayoutConstraint.activate([self.nextCardViewLeadingConstraint!])
    }

    fileprivate func unwindToCurrentPlaceCard(animateWithDuration animationDuration: TimeInterval) {
        currentCardViewCenterXConstraint?.constant = 0
        UIView.animate(withDuration: animationDuration, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
            }, completion: nil )
    }

    fileprivate func addImageCarousel(forNextCard nextCard: PlaceDetailsCardViewController) -> UIView {
        // add the image carousel for the next place card underneath the existing carousel
        // we need to ensure these constraints are applied and rendered before we animate the rest, otherwise we end
        // up with a very odd looking fade transition
        let nextCardImageCarousel = nextCard.imageCarousel
        view.insertSubview(nextCardImageCarousel, belowSubview: imageCarousel)
        NSLayoutConstraint.activate([nextCardImageCarousel.topAnchor.constraint(equalTo: view.topAnchor),
                                     nextCardImageCarousel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                                     nextCardImageCarousel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                     nextCardImageCarousel.heightAnchor.constraint(equalToConstant: imageCarouselHeightConstant)], translatesAutoresizingMaskIntoConstraints: false)

        return nextCardImageCarousel
    }

    func close() {
        self.dismiss(animated: true, completion: nil)
    }

}
