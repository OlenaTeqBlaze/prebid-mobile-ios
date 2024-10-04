/*   Copyright 2018-2021 Prebid.org, Inc.
 
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
 
  http://www.apache.org/licenses/LICENSE-2.0
 
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  */

import UIKit

@objc(PBMBaseInterstitialAdUnit) @objcMembers
class BaseInterstitialAdUnit:
    NSObject,
    PBMInterstitialAdLoaderDelegate,
    AdLoadFlowControllerDelegate,
    InterstitialControllerInteractionDelegate,
    InterstitialEventInteractionDelegate {
    
    // MARK: - Internal Properties
    
    let adUnitConfig: AdUnitConfig
    let eventHandler: PBMPrimaryAdRequesterProtocol
    
    weak var delegate: BaseInterstitialAdUnitProtocol? {
        didSet {
            if let adLoader {
                delegate?.callEventHandler_setLoadingDelegate(adLoader)
            }
        }
    }
    
    var bannerParameters: BannerParameters {
        get { adUnitConfig.adConfiguration.bannerParameters }
    }
    
    var videoParameters: VideoParameters {
        get { adUnitConfig.adConfiguration.videoParameters }
    }
    
    var lastBidResponse: BidResponse? {
        adLoadFlowController?.bidResponse
    }
    
    var isReady: Bool {
        objc_sync_enter(blocksLockToken)
        if let block = isReadyBlock {
            let res = block()
            objc_sync_exit(blocksLockToken)
            return res
        }
        
        objc_sync_exit(blocksLockToken)
        return false
    }
    
    // MARK: - Private Properties
    
    private var adLoadFlowController: PBMAdLoadFlowController!
    
    private let blocksLockToken: NSObject
    private var showBlock: ((UIViewController?) -> Void)?
    private var currentAdBlock: ((UIViewController?) -> Void)?
    private var isReadyBlock: (() -> Bool)?
    private var adLoader: PBMInterstitialAdLoader?
    
    private weak var targetController: UIViewController?
    
    init(
        configID: String,
        minSizePerc: NSValue?,
        eventHandler: PBMPrimaryAdRequesterProtocol
    ) {
        adUnitConfig = AdUnitConfig(configId: configID)
        blocksLockToken = NSObject()
        
        self.eventHandler = eventHandler
        
        super.init()
        
        let adLoader = PBMInterstitialAdLoader(
            delegate: self,
            eventHandler: eventHandler
        )
        
        self.adLoader = adLoader
        
        adLoadFlowController = PBMAdLoadFlowController(
            bidRequesterFactory: { adUnitConfig in
                return PBMBidRequester(
                    connection: PrebidServerConnection.shared,
                    sdkConfiguration: Prebid.shared,
                    targeting: Targeting.shared,
                    adUnitConfiguration: adUnitConfig
                )
            },
            adLoader: adLoader,
            adUnitConfig: adUnitConfig,
            delegate: self,
            configValidationBlock: { _, _ in true }
        )
        
        // Set default values
        adUnitConfig.adConfiguration.isInterstitialAd = true
        adUnitConfig.minSizePerc = minSizePerc
        adUnitConfig.adPosition = .fullScreen
        adUnitConfig.adConfiguration.adFormats = [.banner, .video]
        adUnitConfig.adConfiguration.bannerParameters.api = PrebidConstants.supportedRenderingBannerAPISignals
        videoParameters.placement = .Interstitial
    }
    
    // MARK: - Public Methods
    
    func loadAd() {
        adLoadFlowController.refresh()
    }
    
    func show(from controller: UIViewController) {
        // It is expected from the user to call this method on main thread
        assert(Thread.isMainThread, "Expected to only be called on the main thread");
        
        objc_sync_enter(blocksLockToken)
        
        guard self.showBlock != nil,
              self.currentAdBlock == nil else {
            objc_sync_exit(blocksLockToken)
            return;
        }
        
        isReadyBlock = nil
        currentAdBlock = showBlock
        showBlock = nil
        
        delegate?.callDelegate_willPresentAd()
        targetController = controller
        currentAdBlock?(controller)
        objc_sync_exit(blocksLockToken)
    }
    
    // MARK: - PBMInterstitialAdLoaderDelegate
    
    public func interstitialAdLoader(
        _ interstitialAdLoader: PBMInterstitialAdLoader,
        loadedAd showBlock: @escaping (UIViewController?) -> Void,
        isReadyBlock: @escaping () -> Bool
    ) {
        objc_sync_enter(blocksLockToken)
        self.showBlock = showBlock
        self.isReadyBlock = isReadyBlock
        objc_sync_exit(blocksLockToken)
        
        reportLoadingSuccess()
    }
    
    public func interstitialAdLoader(
        _ interstitialAdLoader: PBMInterstitialAdLoader,
        createdInterstitialController interstitialController: InterstitialController
    ) {
        interstitialController.interactionDelegate = self
    }
    
    // MARK: - AdLoadFlowControllerDelegate
    
    public func adLoadFlowControllerWillSendBidRequest(_ adLoadFlowController: PBMAdLoadFlowController) {}
    
    public func adLoadFlowControllerWillRequestPrimaryAd(_ adLoadFlowController: PBMAdLoadFlowController) {
        delegate?.callEventHandler_setInteractionDelegate()
    }
    
    public func adLoadFlowControllerShouldContinue(_ adLoadFlowController: PBMAdLoadFlowController) -> Bool {
        true
    }
    
    public func adLoadFlowController(
        _ adLoadFlowController: PBMAdLoadFlowController,
        failedWithError error: Error?
    ) {
        reportLoadingFailed(with: error)
    }
    
    // MARK: - InterstitialControllerInteractionDelegate
    
    public func trackImpression(forInterstitialController: InterstitialController) {
        DispatchQueue.main.async {
            self.delegate?.callEventHandler_trackImpression()
        }
    }
    
    public func interstitialControllerDidClickAd(_ interstitialController: InterstitialController) {
        assert(Thread.isMainThread, "Expected to only be called on the main thread")
        delegate?.callDelegate_didClickAd()
    }
    
    public func interstitialControllerDidCloseAd(_ interstitialController: InterstitialController) {
        assert(Thread.isMainThread, "Expected to only be called on the main thread")
        delegate?.callDelegate_didDismissAd()
    }
    
    public func interstitialControllerDidLeaveApp(_ interstitialController: InterstitialController) {
        assert(Thread.isMainThread, "Expected to only be called on the main thread")
        delegate?.callDelegate_willLeaveApplication()
    }
    
    public func interstitialControllerDidDisplay(_ interstitialController: InterstitialController) {}
    public func interstitialControllerDidComplete(_ interstitialController: InterstitialController) {}
    
    public func viewControllerForModalPresentation(
        fromInterstitialController: InterstitialController
    ) -> UIViewController? {
        return targetController
    }
    
    // MARK: - InterstitialEventInteractionDelegate
    
    public func willPresentAd() {
        DispatchQueue.main.async {
            self.delegate?.callDelegate_willPresentAd()
        }
    }
    
    public func didDismissAd() {
        objc_sync_enter(blocksLockToken)
        currentAdBlock = nil
        objc_sync_exit(blocksLockToken)
        
        DispatchQueue.main.async {
            self.delegate?.callDelegate_didDismissAd()
        }
    }
    
    public func willLeaveApp() {
        DispatchQueue.main.async {
            self.delegate?.callDelegate_willLeaveApplication()
        }
    }
    
    public func didClickAd() {
        DispatchQueue.main.async {
            self.delegate?.callDelegate_didClickAd()
        }
    }
    
    // MARK: - Private methods
    
    private func reportLoadingSuccess() {
        DispatchQueue.main.async {
            self.delegate?.callDelegate_didReceiveAd()
        }
    }
    
    private func reportLoadingFailed(with error: Error?) {
        DispatchQueue.main.async {
            self.delegate?.callDelegate_didFailToReceiveAd(with: error)
        }
    }
}
