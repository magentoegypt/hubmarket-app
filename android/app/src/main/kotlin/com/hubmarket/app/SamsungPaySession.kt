package com.hubmarket.app

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.samsung.android.sdk.samsungpay.v2.SpaySdk
import com.samsung.android.sdk.samsungpay.v2.StatusListener
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject
import payment.sdk.android.core.Order
import payment.sdk.android.core.api.CoroutinesGatewayHttpClient
import payment.sdk.android.samsungpay.SamsungPayClient
import payment.sdk.android.samsungpay.SamsungPayResponse

/**
 * Samsung Pay half of the `hubmarket/payments` channel (contract §③, `wallet=samsungpay`).
 *
 * Samsung Pay is NOT a separate gateway: [SamsungPayClient.startSamsungPay] drives the
 * very same N-Genius order the card path uses — it reads `_links.payment-authorization`
 * and `_links.payment` out of the order to authorize, exactly like `PaymentsLauncher`
 * does. So the backend session payload is unchanged and only the SDK entry point differs.
 *
 * Everything Samsung-specific lives here so [PaymentChannel] stays a dispatcher.
 */
class SamsungPaySession(private val activity: Activity) {

    companion object {
        /**
         * Hard ceiling on the availability check. Dart awaits this while building the
         * checkout payment step, and the answer comes back over a binder to another
         * app — which can be slow, mid-update, or simply never reply.
         */
        private const val AVAILABILITY_TIMEOUT_MS = 1_500L

        /** `"...failed with code -7 (User canceled)"` — the int is the SpaySdk error. */
        private val ERROR_CODE = Regex("failed with code (-?\\d+)")

        /**
         * Maps the SDK's single failure string to a canonical status.
         *
         * [SamsungPayResponse] only distinguishes success from failure, but the message
         * `SamsungPayTransactionListener` builds embeds the numeric SpaySdk error, so a
         * user-cancelled sheet is recoverable — and it matters, because cancelled shows
         * different copy than failed on the complete-payment screen.
         *
         * Nothing maps to DECLINED on purpose. A gateway decline arrives as an opaque
         * code, and guessing which codes mean "declined" would put wrong copy in front
         * of the customer. DECLINED and FAILED both route to CompletePaymentScreen
         * anyway, and the exact SDK string is preserved in `raw` for PaymentTrace.
         */
        internal fun mapFailure(message: String?): Pair<String, String?> {
            val raw = message?.takeIf { it.isNotEmpty() }?.let { "samsungpay: $it" }
            val code = message?.let {
                ERROR_CODE.find(it)?.groupValues?.getOrNull(1)?.toIntOrNull()
            }
            return if (code == SpaySdk.ERROR_USER_CANCELED) {
                "CANCELLED" to raw
            } else {
                "FAILED" to raw
            }
        }

        /**
         * Builds the SDK's [Order] from the raw order JSON.
         *
         * Hand-built rather than deserialized: Gson ships with payment-sdk-core in
         * `runtimeElements` only, so it is invisible to the compiler, and `org.json` is
         * already what [PaymentChannel] uses. These are exactly the fields
         * `startSamsungPay` reads — outlet id, reference, amount, card schemes, the two
         * order links it authorizes against, and the `payment:samsung_pay` link.
         */
        internal fun buildOrder(orderJson: String?): Order? {
            if (orderJson.isNullOrEmpty()) return null
            return try {
                val root = JSONObject(orderJson)
                Order().apply {
                    val rootLinks = root.optJSONObject("_links")
                    links = Order.Links().apply {
                        paymentAuthorizationUrl = href(rootLinks, "payment-authorization")
                        paymentUrl = href(rootLinks, "payment")
                    }
                    outletId = root.optString("outletId").ifEmpty { null }
                    reference = root.optString("reference").ifEmpty { null }
                    amount = root.optJSONObject("amount")?.let { node ->
                        Order.Amount().apply {
                            currencyCode = node.optString("currencyCode").ifEmpty { null }
                            value = if (node.has("value")) node.optDouble("value") else null
                        }
                    }
                    paymentMethods = root.optJSONObject("paymentMethods")?.let { node ->
                        Order.PaymentMethods().apply {
                            card = node.optJSONArray("card")?.let { array ->
                                List(array.length()) { array.optString(it) }
                            }
                        }
                    }
                    embedded = root.optJSONObject("_embedded")
                        ?.optJSONArray("payment")
                        ?.let { array ->
                            Order.Embedded().apply {
                                payment = Array(array.length()) { index ->
                                    val node = array.optJSONObject(index)
                                    Order.Payment().apply {
                                        outletId = node?.optString("outletId")?.ifEmpty { null }
                                        links = Order.PaymentLinks().apply {
                                            samsungPayLink = href(
                                                node?.optJSONObject("_links"),
                                                "payment:samsung_pay",
                                            )
                                        }
                                    }
                                }
                            }
                        }
                }
            } catch (error: Exception) {
                null
            }
        }

        private fun href(links: JSONObject?, name: String): Order.Href? =
            links?.optJSONObject(name)?.optString("href")
                ?.takeIf { it.isNotEmpty() }
                ?.let { value -> Order.Href().apply { href = value } }
    }

    /** Positives only — a negative can be transient (Samsung Wallet mid-update). */
    private var cachedAvailability: Boolean? = null

    /**
     * Whether this device can pay with Samsung Pay: a Samsung handset, Samsung Wallet
     * installed and up to date, our package + signature registered in the Samsung Pay
     * portal, and at least one provisioned card. Answers exactly once, always.
     */
    fun checkAvailability(serviceId: String, onResult: (Boolean) -> Unit) {
        // A blank service id must never reach the client: SamsungPayBase's constructor
        // throws NullPointerException("Context and PartnerInfo.serviceId have to be
        // set.") before any listener is attached.
        if (serviceId.isBlank()) {
            onResult(false)
            return
        }
        cachedAvailability?.let {
            onResult(it)
            return
        }

        val settled = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        val answer = { available: Boolean ->
            if (settled.compareAndSet(false, true)) {
                handler.removeCallbacksAndMessages(null)
                if (available) cachedAvailability = true
                onResult(available)
            }
        }

        try {
            val client = SamsungPayClient(activity, serviceId, CoroutinesGatewayHttpClient())
            handler.postDelayed({ answer(false) }, AVAILABILITY_TIMEOUT_MS)
            client.isSamsungPayAvailable(object : StatusListener {
                override fun onSuccess(status: Int, bundle: Bundle) {
                    answer(status == SpaySdk.SPAY_READY)
                }

                override fun onFail(errorCode: Int, bundle: Bundle) {
                    answer(false)
                }
            })
        } catch (error: Throwable) {
            answer(false)
        }
    }

    /**
     * Presents the Samsung Pay sheet for [orderJson] and resolves once with a canonical
     * status.
     */
    fun start(
        serviceId: String,
        merchantName: String,
        orderJson: String?,
        onResult: (status: String, raw: String?) -> Unit,
    ) {
        val settled = AtomicBoolean(false)
        val answer = { status: String, raw: String? ->
            if (settled.compareAndSet(false, true)) onResult(status, raw)
        }

        val order = buildOrder(orderJson)
        if (order == null) {
            answer("FAILED", "samsungpay: orderResponse missing or did not parse")
            return
        }

        // Pre-flight the SDK's own guards so the reason we report is precise. Without
        // the samsung_pay link the SDK answers a bare "Samsung Pay is not enabled",
        // which reads like a device problem when it is actually outlet configuration.
        if (order.links?.paymentAuthorizationUrl?.href.isNullOrEmpty() ||
            order.links?.paymentUrl?.href.isNullOrEmpty()
        ) {
            answer("FAILED", "samsungpay: missing payment links in orderResponse")
            return
        }
        if (order.embedded?.payment?.firstOrNull()?.links?.samsungPayLink?.href.isNullOrEmpty()) {
            answer("FAILED", "samsungpay: outlet not enabled (no payment:samsung_pay link)")
            return
        }

        try {
            SamsungPayClient(activity, serviceId, CoroutinesGatewayHttpClient())
                .startSamsungPay(
                    order,
                    merchantName,
                    object : SamsungPayResponse {
                        // Reached only after N-Genius accepted the encrypted token.
                        // Capture state is unknown, so report AUTHORISED rather than
                        // SUCCESS — Dart maps both to success and re-queries Magento.
                        override fun onSuccess() {
                            answer("AUTHORISED", null)
                        }

                        override fun onFailure(error: String) {
                            val (status, raw) = mapFailure(error)
                            answer(status, raw)
                        }
                    },
                )
        } catch (error: Throwable) {
            // Mandatory: if the Samsung SDK throws synchronously no callback ever
            // fires, and the Flutter result would hang for the rest of the session.
            answer("FAILED", "samsungpay: ${error.javaClass.simpleName} ${error.message}")
        }
    }
}
