import Foundation

@MainActor
extension PangguaiStore {
    private func laundryChannels(_ raw: PGJSON) throws -> [PGChannel] {
        let rows = try raw.rows(); guard rows.count <= 30 else { throw PGFailure.format }
        var seen = Set<String>()
        return rows.compactMap { row in
            let method = row["method"].text
            guard ["2", "13"].contains(method), seen.insert(method).inserted else { return nil }
            let enabled = row["useStatus"].yes && ["false", "0"].contains(row["needOpenFlag"].text)
            // Android PayTask is not an iOS SDK. Never put its signed parameters in a guessed URL.
            return PGChannel(id: method, name: row["methodName"].text.isEmpty ? (method == "2" ? "余额支付" : "支付宝") : String(row["methodName"].text.prefix(40)), available: enabled && method == "2", reason: method == "13" ? "请在支付宝胖乖小程序完成此订单" : String(row["notUseRemark"].text.prefix(120)))
        }
    }
    private func buildLaundryQuote(_ d: PGDevice, skuID: String, epoch: UUID) async throws -> PGLaundryQuote {
        guard d.category == "00", d.payment == "before", d.isBluetooth == "0", d.issue.isEmpty,
              !d.imei.isEmpty, !d.routeShopID.isEmpty, !d.shopID.isEmpty,
              let sku = d.skus.first(where: { $0.id == skuID && $0.available }) else { throw PGFailure.device }
        let items = try PangguaiProtocol.items(device: d.id, sku: skuID)
        let preview = try await post("trade/preview/v4", ["items": items, "promotions":"[]", "forbiddenPromotions":"[]", "isAutoSelectPromotion":"0"], epoch: epoch)
        let rows = try preview["items"].rows()
        guard rows.count == 1, rows[0]["goodsId"].text == d.id, rows[0]["skuId"].text == skuID else { throw PGFailure.device }
        let amount = try PangguaiProtocol.price(preview["realPrice"])
        let channelData = try await post("payChannelRoute/prePay", ["imei":d.imei, "goodsId":d.id, "hitAd":"0", "payPrice":amount, "useTicket":"0", "shopId":d.routeShopID, "combineOrderStatus":"false", "confirmSelectedStatus":"false"], epoch: epoch)
        return PGLaundryQuote(expiresAt: now().addingTimeInterval(60), deviceID: d.id, deviceName: d.name, skuID: skuID, program: sku.name, amount: amount, channels: try laundryChannels(channelData))
    }
    func quoteLaundry(skuID: String? = nil) async {
        await perform { epoch in
            self.laundryQuote = nil
            if let skuID, let device = self.device {
                guard self.snapshot.laundry?.terminal != false else { throw PGFailure.orderActive }
                self.laundryQuote = try await self.buildLaundryQuote(device, skuID: skuID, epoch: epoch)
            } else if let source = self.snapshot.laundry {
                self.laundryQuote = try await self.existingLaundryQuote(source, epoch: epoch)
            } else { throw PGFailure.device }
        }
    }
    private func existingLaundryQuote(_ source: PGLaundrySession, epoch: UUID) async throws -> PGLaundryQuote {
        let s = try await readLaundry(source, epoch: epoch)
        guard s.phase == "pending", !s.paySent, !s.cancelSent, let number = s.orderNo else { throw PGFailure.orderActive }
        let channels = try await post("payChannelRoute/againPay", ["orderNo":number, "shopId":s.shopID, "confirmSelectedStatus":"false"], epoch: epoch)
        return PGLaundryQuote(expiresAt: now().addingTimeInterval(60), deviceID: s.deviceID, deviceName: s.deviceName, skuID: s.skuID, program: s.program, amount: s.amount, channels: try laundryChannels(channels), sessionID: s.id)
    }
    private func requireAllowed(_ q: PGLaundryQuote, method: String) throws {
        guard now() <= q.expiresAt else { throw PGFailure.quoteExpired }
        guard method == "2", q.channels.contains(where: { $0.id == method && $0.available }) else { throw PGFailure.payChannel }
    }
    private func laundryReady(_ id: String, epoch: UUID) async throws {
        let check = try await post("trade/check_device_status", ["goodsId":id], epoch: epoch)
        guard check["health"].yes else { throw PGFailure.deviceBusy }
        let message = try check.required("msgId")
        for _ in 0..<8 {
            if try await post("machine/sync", ["msgId":message], epoch: epoch).yes { return }
            try await Task.sleep(nanoseconds: 750_000_000); try alive(epoch)
        }
        throw PGFailure.deviceBusy
    }
    /// Only called by the explicit fee-review confirmation button. The quote is consumed before any request.
    func startLaundry(confirmedQuoteID: UUID, method: String) async {
        await perform { epoch in
            guard let q = self.laundryQuote, q.id == confirmedQuoteID else { throw PGFailure.quoteExpired }
            self.laundryQuote = nil
            try self.requireAllowed(q, method: method)
            if let sessionID = q.sessionID {
                guard let old = self.snapshot.laundry, old.id == sessionID else { throw PGFailure.orderMismatch }
                let fresh = try await self.existingLaundryQuote(old, epoch: epoch)
                try self.requireAllowed(fresh, method: method)
                guard fresh.amount == q.amount else { throw PGFailure.priceChanged }
                try await self.laundryReady(old.deviceID, epoch: epoch)
                guard let current = self.snapshot.laundry, current.id == sessionID, current.phase == "pending", !current.paySent else { throw PGFailure.orderActive }
                try self.requireAllowed(q, method: method)
                try await self.payLaundry(current, method: method, epoch: epoch)
                return
            }
            guard let device = self.device, device.id == q.deviceID else { throw PGFailure.device }
            guard self.snapshot.laundry?.terminal != false else { throw PGFailure.orderActive }
            let fresh = try await self.buildLaundryQuote(device, skuID: q.skuID, epoch: epoch)
            try self.requireAllowed(fresh, method: method)
            guard fresh.amount == q.amount, fresh.program == q.program else { throw PGFailure.priceChanged }
            try await self.laundryReady(device.id, epoch: epoch)
            let previous = try await self.post("order/list", ["page":"1", "pageSize":"20"], epoch: epoch)
            let known = try previous["items"].rows().map { try $0.required("id") }
            guard known.count <= 20 else { throw PGFailure.format }
            var s = PGLaundrySession(deviceID: device.id, deviceName: device.name, skuID: q.skuID, program: q.program, shopID: device.shopID, amount: q.amount)
            s.createSentAt = self.now(); s.updatedAt = self.now(); s.knownOrders = known
            try self.requireAllowed(q, method: method)
            try self.saveLaundry(s, epoch: epoch) // Durable intent precedes trade/create. Never replay on unknown outcome.
            do {
                let created = try await self.post("trade/create", ["items":try PangguaiProtocol.items(device: device.id, sku: q.skuID), "promotions":"[]"], epoch: epoch)
                s.orderNo = try created.required("tradeNo"); s.orderID = try created.required("orderId"); s.phase = "pending"
                try self.saveLaundry(s, epoch: epoch)
                s = try await self.readLaundry(s, epoch: epoch)
                guard s.phase == "pending", !s.paySent, s.amount == q.amount else { throw PGFailure.priceChanged }
                try self.requireAllowed(q, method: method)
                try await self.payLaundry(s, method: method, epoch: epoch)
            } catch { try self.recordLaundryError(id: s.id, error: error, epoch: epoch); throw error }
        }
    }
    private func payLaundry(_ source: PGLaundrySession, method: String, epoch: UUID) async throws {
        guard method == "2", source.phase == "pending", !source.paySent, !source.cancelSent, let number = source.orderNo else { throw PGFailure.orderActive }
        var s = source; s.method = method; s.paySent = true; s.phase = "checking"; s.updatedAt = now()
        try saveLaundry(s, epoch: epoch)
        do {
            _ = try await post("pay/unify/pay", ["orderNo":number, "payType":method], epoch: epoch)
            _ = try await readLaundry(s, epoch: epoch)
        } catch { try recordLaundryError(id: s.id, error: error, epoch: epoch); throw error }
    }
    private func recordLaundryError(id: UUID, error: Error, epoch: UUID) throws {
        try alive(epoch)
        if var current = snapshot.laundry, current.id == id { current.error = PGFailure.mapped(error); try saveLaundry(current, epoch: epoch) }
    }
    func readLaundry(_ source: PGLaundrySession, epoch: UUID) async throws -> PGLaundrySession {
        var s = source
        do {
            if s.orderNo == nil { s = try await recoverLaundry(s, epoch: epoch) }
            guard let number = s.orderNo, let id = s.orderID else { throw PGFailure.createUnknown }
            let d = try await post("order/detail", ["orderNo":number], epoch: epoch)
            let rows = try (d["tradeOrderItem"].array != nil ? d["tradeOrderItem"] : d["lineItems"]).rows()
            guard d["orderNo"].text == number, d["id"].text == id, rows.count == 1,
                  rows[0]["goodsId"].text == s.deviceID, rows[0]["skuId"].text == s.skuID else { throw PGFailure.orderMismatch }
            let phase = ["0":s.paySent ? "checking":"pending", "1":"closed", "2":"paid", "3":"completed", "4":"refunding", "5":"refunded"][d["orderStatus"].text] ?? "unknown"
            guard phase != "unknown" else { throw PGFailure.format }
            let regression = (["pending","checking","paid"].contains(phase) && ["running","completed","refunded"].contains(s.phase)) || (["pending","checking"].contains(phase) && s.phase == "paid")
            if !regression { s.phase = phase }
            s.amount = try PangguaiProtocol.price(d["payPrice"]); s.updatedAt = now(); s.error = nil
            s.expectedEnd = PangguaiProtocol.timestamp(d["completeTime"].text) ?? s.expectedEnd
            s.finishedAt = PangguaiProtocol.timestamp(d["finishTime"].text) ?? s.finishedAt
            try saveLaundry(s, epoch: epoch)
            if ["checking","pending"].contains(s.phase), let method = s.method, try await post("order/pay_status", ["orderNo":number, "payType":method], epoch: epoch).yes {
                s.phase = "paid"; try saveLaundry(s, epoch: epoch)
            }
            if ["paid","running"].contains(s.phase), try await post("machine/device_is_start", ["orderNo":number], epoch: epoch).yes {
                s.phase = "running"; try saveLaundry(s, epoch: epoch)
            }
            return s
        } catch { try recordLaundryError(id: source.id, error: error, epoch: epoch); throw error }
    }
    private func recoverLaundry(_ source: PGLaundrySession, epoch: UUID) async throws -> PGLaundrySession {
        let result = try await post("order/list", ["page":"1", "pageSize":"20"], epoch: epoch)
        let rows = try result["items"].rows(); guard rows.count <= 20 else { throw PGFailure.format }
        let matches = rows.filter { row in
            let items = row["tradeOrderItem"].array ?? row["lineItems"].array ?? []
            guard let created = PangguaiProtocol.timestamp(row["createTime"].text) else { return false }
            return !row["id"].text.isEmpty && !source.knownOrders.contains(row["id"].text) && !row["orderNo"].text.isEmpty && items.count == 1 && items[0]["goodsId"].text == source.deviceID && items[0]["skuId"].text == source.skuID && created >= source.createSentAt.addingTimeInterval(-5) && created <= source.createSentAt.addingTimeInterval(120)
        }
        guard matches.count == 1 else { throw PGFailure.createUnknown }
        var candidate = source; candidate.orderNo = try matches[0].required("orderNo"); candidate.orderID = try matches[0].required("id")
        // The caller validates order/detail before saving the adopted identity. Recovery never pays.
        return candidate
    }
    func cancelLaundry(confirmedSessionID: UUID) async {
        await perform { epoch in
            guard let source = self.snapshot.laundry, source.id == confirmedSessionID else { throw PGFailure.orderMismatch }
            var s = try await self.readLaundry(source, epoch: epoch)
            guard ["pending", "checking"].contains(s.phase), let id = s.orderID else { throw PGFailure.orderActive }
            if !s.cancelSent {
                s.cancelSent = true; try self.saveLaundry(s, epoch: epoch)
                _ = try await self.post("order/cancel", ["orderId":id], epoch: epoch)
            }
            _ = try await self.readLaundry(s, epoch: epoch)
        }
    }
}
