package com.hubmarket.app

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import payment.sdk.android.payments.PaymentsLauncher
import payment.sdk.android.payments.PaymentsRequest
import payment.sdk.android.payments.PaymentsResult
import payment.sdk.android.savedCard.SavedCardPaymentLauncher
import payment.sdk.android.savedCard.SavedCardPaymentRequest

/**
 * Android half of the `hubmarket/payments` MethodChannel — the N-Genius (Network
 * International) card SDK and its Samsung Pay wallet. Contract:
 * docs/backend/payment-contract.md §③.
 *
 * Apple Pay and Samsung Pay are N-Genius *wallets*, not gateways: the `gateway`
 * argument stays `ngenius` for all three and the `wallet` argument selects the
 * SDK entry point. Both ride the same order JSON.
 *
 * Tabby is deliberately not handled here: its SDK ships as a Flutter package
 * (`tabby_flutter_inapp_sdk`), so it lives in Dart and needs no native code on
 * either platform.
 *
 * The launcher is owned by [MainActivity], because `registerForActivityResult`
 * has to run before the activity reaches STARTED and therefore cannot be
 * created on demand when `pay` arrives.
 */
class PaymentChannel {
    companion object {
        private const val CHANNEL = "hubmarket/payments"

        /** Order JSON link names — see the SDK's Order model (`_links`). */
        private const val LINK_AUTHORIZATION = "payment-authorization"
        private const val LINK_PAY_PAGE = "payment"

        /** Present on the order JSON when the backend attached a stored card. */
        private const val NODE_SAVED_CARD = "savedCard"

        private const val WALLET_CARD = "card"
        private const val WALLET_APPLE_PAY = "applepay"
        private const val WALLET_SAMSUNG_PAY = "samsungpay"
    }

    private var launcher: PaymentsLauncher? = null
    private var savedCardLauncher: SavedCardPaymentLauncher? = null
    private var samsung: SamsungPaySession? = null

    /**
     * The in-flight Flutter result. Held because the SDK answers on an activity
     * result long after `pay` returns; without it the callback would have
     * nothing to resolve and checkout would hang.
     */
    private var pending: MethodChannel.Result? = null
    private var pendingOrderNumber: String = ""

    /**
     * Ownership token for [pending]. A wallet callback can arrive late — after the
     * customer already backed out and started a card payment — and resolving the
     * wrong (or an already-resolved) result throws. Only the holder of the current
     * token may resolve.
     */
    private var pendingToken: Long = 0
    private var tokenSeq: Long = 0
    private var cardToken: Long = 0

    fun attach(
        engine: FlutterEngine,
        launcher: PaymentsLauncher,
        savedCardLauncher: SavedCardPaymentLauncher,
        activity: Activity,
    ) {
        this.launcher = launcher
        this.savedCardLauncher = savedCardLauncher
        this.samsung = SamsungPaySession(activity)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pay" -> handlePay(call, result)
            "walletAvailability" -> handleWalletAvailability(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handlePay(call: MethodCall, result: MethodChannel.Result) {
        // Anything that isn't N-Genius is handled in Dart. Reporting "not
        // implemented" lets the Dart layer fall back rather than fail hard.
        if (call.argument<String>("gateway") != "ngenius") {
            result.notImplemented()
            return
        }

        val orderNumber = call.argument<String>("orderNumber").orEmpty()
        when (call.argument<String>("wallet") ?: WALLET_CARD) {
            WALLET_CARD -> startCard(call, result, orderNumber)
            WALLET_SAMSUNG_PAY -> startSamsungPay(call, result, orderNumber)
            // FAILED rather than notImplemented(): "not implemented" means "the
            // native module is missing", which Dart turns into "order awaiting
            // payment". That would be a lie here — this can only be a Dart bug,
            // since walletAvailability already answers applePay=false on Android,
            // and FAILED surfaces it in the payment trace.
            WALLET_APPLE_PAY -> result.success(
                payload("FAILED", orderNumber, raw = "applepay is iOS-only"),
            )
            else -> result.success(
                payload("FAILED", orderNumber, raw = "unsupported wallet"),
            )
        }
    }

    private fun startCard(
        call: MethodCall,
        result: MethodChannel.Result,
        orderNumber: String,
    ) {
        val orderJson = call.argument<String>("orderResponse")

        // Two DIFFERENT order links are required: _links.payment-authorization
        // (the API the SDK authorizes against) and _links.payment (the hosted
        // pay page, which carries the ?code=). Swapping them makes the SDK
        // authorize against the pay page, which answers with an HTML error
        // page rather than a usable response.
        //
        // The order JSON stays authoritative; the channel arguments are a
        // fallback for when order_response is absent.
        val links = parseLinks(orderJson)
        val authorizationUrl = links[LINK_AUTHORIZATION]
            ?: call.argument<String>("authorizationHref")
        val payPageUrl = links[LINK_PAY_PAGE]
            ?: call.argument<String>("payPageHref")

        if (authorizationUrl.isNullOrEmpty() || payPageUrl.isNullOrEmpty()) {
            result.success(
                payload(
                    status = "FAILED",
                    orderNumber = orderNumber,
                    raw = "missing payment links (authorization=" +
                        "${!authorizationUrl.isNullOrEmpty()}, " +
                        "payPage=${!payPageUrl.isNullOrEmpty()})",
                ),
            )
            return
        }

        // A stored card is a different SDK activity: it renders the saved card
        // and recaptures only the CVV. Which one to open is decided here rather
        // than by a channel argument, because the order JSON is authoritative —
        // the backend attaches `savedCard` to the N-Genius order when the quote
        // carried a vault token (docs/backend/payment-contract.md §④), and the
        // SDK reads it from that same order. No CVV crosses the channel; the
        // SDK's own capture screen collects it.
        if (hasSavedCard(orderJson)) {
            val activeSavedCard = savedCardLauncher
            if (activeSavedCard == null) {
                result.success(
                    payload("FAILED", orderNumber, raw = "saved-card launcher unavailable"),
                )
                return
            }
            cardToken = claimPending(result, orderNumber)
            activeSavedCard.launch(
                SavedCardPaymentRequest.builder()
                    .gatewayAuthorizationUrl(authorizationUrl)
                    .payPageUrl(payPageUrl)
                    .build(),
            )
            return
        }

        val activeLauncher = launcher
        if (activeLauncher == null) {
            result.success(
                payload("FAILED", orderNumber, raw = "payment launcher unavailable"),
            )
            return
        }

        cardToken = claimPending(result, orderNumber)

        activeLauncher.launch(
            PaymentsRequest.builder()
                .gatewayAuthorizationUrl(authorizationUrl)
                .payPageUrl(payPageUrl)
                .build(),
        )
    }

    /**
     * Whether the order carries a stored card. Tolerates a malformed body the
     * same way [parseLinks] does — an unreadable order falls back to the normal
     * card form, which is the recoverable direction.
     */
    private fun hasSavedCard(orderJson: String?): Boolean {
        if (orderJson.isNullOrEmpty()) return false
        return try {
            JSONObject(orderJson).optJSONObject(NODE_SAVED_CARD) != null
        } catch (error: Exception) {
            false
        }
    }

    private fun startSamsungPay(
        call: MethodCall,
        result: MethodChannel.Result,
        orderNumber: String,
    ) {
        val serviceId = call.argument<String>("samsungPayServiceId").orEmpty()
        if (serviceId.isBlank()) {
            result.success(
                payload("FAILED", orderNumber, raw = "samsungpay: no service id configured"),
            )
            return
        }
        val session = samsung
        if (session == null) {
            result.success(
                payload("FAILED", orderNumber, raw = "samsungpay: session unavailable"),
            )
            return
        }

        val token = claimPending(result, orderNumber)
        session.start(
            serviceId = serviceId,
            merchantName = call.argument<String>("merchantName").orEmpty().ifEmpty { "Hub Market" },
            orderJson = call.argument<String>("orderResponse"),
        ) { status, raw -> resolvePending(token, status, raw) }
    }

    /**
     * Which wallets this device can pay with. Deliberately independent of
     * [pending]: the checkout list asks this while a payment may be in flight,
     * and answering must never retire someone else's result.
     */
    private fun handleWalletAvailability(call: MethodCall, result: MethodChannel.Result) {
        val serviceId = call.argument<String>("samsungPayServiceId").orEmpty()
        val session = samsung
        if (serviceId.isBlank() || session == null) {
            result.success(mapOf("applePay" to false, "samsungPay" to false))
            return
        }
        session.checkAvailability(serviceId) { available ->
            // applePay is always false on Android — the row is hidden even if the
            // backend offers the method to every device.
            result.success(mapOf("applePay" to false, "samsungPay" to available))
        }
    }

    /**
     * Retires any in-flight payment as cancelled and installs this one. Only one
     * payment can be presented at a time, and resolving a MethodChannel.Result
     * twice throws.
     */
    private fun claimPending(result: MethodChannel.Result, orderNumber: String): Long {
        pending?.success(payload("CANCELLED", pendingOrderNumber, raw = "superseded"))
        pending = result
        pendingOrderNumber = orderNumber
        pendingToken = ++tokenSeq
        return pendingToken
    }

    /** No-ops unless [token] still owns the pending result. */
    private fun resolvePending(token: Long, status: String, raw: String? = null) {
        if (token != pendingToken) return
        val target = pending ?: return
        pending = null
        pendingToken = 0
        val orderNumber = pendingOrderNumber
        pendingOrderNumber = ""
        target.success(payload(status, orderNumber, raw = raw))
    }

    /** Invoked by [MainActivity] when the SDK's activity returns. */
    fun onPaymentResult(result: PaymentsResult) {
        val (status, raw) = when (result) {
            // Authorised now, captured later — the contract treats both as
            // success and the app re-queries Magento for the real state.
            is PaymentsResult.Authorised -> "AUTHORISED" to null
            is PaymentsResult.Success -> "SUCCESS" to null
            is PaymentsResult.PostAuthReview -> "POST_AUTH_REVIEW" to null

            is PaymentsResult.PartialAuthDeclined,
            is PaymentsResult.PartialAuthDeclineFailed,
            -> "DECLINED" to result::class.simpleName

            // Only part of the amount cleared. Passed through unmapped so Dart
            // treats it as failed and routes to CompletePaymentScreen, rather
            // than showing success for an order that isn't fully paid. Matches
            // the iOS module.
            is PaymentsResult.PartiallyAuthorised -> "PARTIALLY_AUTHORISED" to null

            is PaymentsResult.Cancelled -> "CANCELLED" to null
            is PaymentsResult.Failed -> "FAILED" to result.error
        }
        resolvePending(cardToken, status, raw)
    }

    /** Reads `_links` out of the raw order JSON, tolerating a malformed body. */
    private fun parseLinks(orderJson: String?): Map<String, String> {
        if (orderJson.isNullOrEmpty()) return emptyMap()
        return try {
            val links = JSONObject(orderJson).optJSONObject("_links")
                ?: return emptyMap()
            listOf(LINK_AUTHORIZATION, LINK_PAY_PAGE)
                .mapNotNull { name ->
                    links.optJSONObject(name)?.optString("href")
                        ?.takeIf { it.isNotEmpty() }
                        ?.let { name to it }
                }
                .toMap()
        } catch (error: Exception) {
            emptyMap()
        }
    }

    /** Result map shape from the contract. */
    private fun payload(
        status: String,
        orderNumber: String,
        reference: String? = null,
        raw: String? = null,
    ): Map<String, Any> = buildMap {
        put("status", status)
        put("gateway", "ngenius")
        put("orderNumber", orderNumber)
        reference?.let { put("reference", it) }
        raw?.let { put("raw", it) }
    }
}
