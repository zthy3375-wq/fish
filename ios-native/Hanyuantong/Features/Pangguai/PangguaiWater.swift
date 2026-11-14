import Foundation

@MainActor
extension PangguaiStore {
    private func buildWaterQuote(_ device: PGDevice, skuID: String, epoch: UUID) async throws -> PGWaterQuote {
        guard device.category == "04", !device.routeShopID.isEmpty else { throw PGFailure.device }
        let d = try await post("goods/normal/details", ["goodsId":device.id], epoch: epoch)
        guard d["goodsId"].text == device.id, d["categoryCode"].text == "04", d["payment"].text == "after", d["isBluetooth"].text == "0" else { throw PGFailure.device }
        guard d["deviceErrorMsg"].text.isEmpty else { throw PGFailure.deviceBusy }
        let raw = try await post("goods/normal/skus", ["goodsId":device.id], epoch: epoch)
        let rows = try raw.rows(); guard rows.count <= 40 else { throw PGFailure.format }
        let matches = rows.filter { $0["skuId"].text == skuID && $0["scanAvailable"].yes && $0["stockState"].text == "1" }
        guard matches.count == 1 else { throw PGFailure.deviceBusy }; let sku = matches[0]
        let data = try await post("payChannelRoute/afterPay", ["imei":try d.required("imei"), "useTicket":"0", "shopId":device.routeShopID, "goodsCategory":"04"], epoch: epoch)
        let channels = try data.rows(); guard channels.count <= 30 else { throw PGFailure.format }
        let channel = channels.first { $0["method"].text == "15" }
        let price = PangguaiProtocol.money(sku["price"]), feature = String(sku["feature"].text.prefix(300))
        let usable = channel?["useStatus"].yes == true && ["false", "0"].contains(channel?["needOpenFlag"].text ?? "")
        let canStart = usable && price != nil && !feature.isEmpty
        let reason: String
        if !usable { reason = "请先在支付宝胖乖小程序核对本账户的免密付款渠道。" }
        else if price == nil || feature.isEmpty { reason = "计费信息不完整，请在机身或官方端核对后使用。" }
        else { reason = "" }
        let payment = String((channel?["methodName"].text ?? "").prefix(50))
        return PGWaterQuote(expiresAt: now().addingTimeInterval(60), deviceID: device.id, deviceName: try d.required("name"), skuID: skuID, outlet: String(sku["name"].text.prefix(100)), feature: feature, price: price, paymentName: payment.isEmpty ? "支付宝免密" : payment, remoteEnd: d["supportAppUserFinish"].yes, canStart: canStart, reason: reason)
    }
    func prepareWater(skuID: String) async {
        await perform { epoch in
            self.waterQuote = nil
            guard let d = self.device else { throw PGFailure.device }
            if let old = self.snapshot.water, !old.terminal { throw PGFailure.waterActive }
            self.waterQuote = try await self.buildWaterQuote(d, skuID: skuID, epoch: epoch)
        }
    }
    private func waterReading(skuID: String, epoch: UUID) async throws -> PGJSON? {
        let data = try await post("goods/water/sync", ["skuId":skuID], epoch: epoch)
        if data == .null { return nil }; return try data.record()
    }
    /// Metered start is possible only after explicit review of account, outlet, rate and after-pay method.
    func startWater(confirmedQuoteID: UUID) async {
        await perform { epoch in
            guard let q = self.waterQuote, q.id == confirmedQuoteID else { throw PGFailure.quoteExpired }
            self.waterQuote = nil
            guard self.now() <= q.expiresAt else { throw PGFailure.quoteExpired }
            if let old = self.snapshot.water, !old.terminal { throw PGFailure.waterActive }
            guard let device = self.device, device.id == q.deviceID else { throw PGFailure.device }
            guard q.canStart else { throw PGFailure.waterChannel }
            let fresh = try await self.buildWaterQuote(device, skuID: q.skuID, epoch: epoch)
            guard fresh.canStart else { throw PGFailure.waterChannel }
            guard fresh.price == q.price, fresh.feature == q.feature, fresh.outlet == q.outlet, fresh.paymentName == q.paymentName, fresh.remoteEnd == q.remoteEnd else { throw PGFailure.priceChanged }
            let before = try await self.waterReading(skuID: q.skuID, epoch: epoch)
            guard before?["workStatus"].text != "2" else { throw PGFailure.deviceBusy }
            // A nonempty reading must explicitly report idle. status=5 belongs to
            // end reconciliation, not to the precondition for a new session.
            if let before, before["workStatus"].text != "1" { throw PGFailure.waterWait }
            guard self.now() <= q.expiresAt else { throw PGFailure.quoteExpired }
            _ = try await self.post("payChannelRoute/addUserAfterPayChannel", ["method":"15"], epoch: epoch)
            var s = PGWaterSession(deviceID: device.id, deviceName: fresh.deviceName, skuID: q.skuID, outlet: fresh.outlet, feature: fresh.feature, paymentName: fresh.paymentName, remoteEnd: fresh.remoteEnd)
            s.updatedAt = self.now(); try self.saveWater(s, epoch: epoch)
            do {
                let rows = ["-6", "-7", "-8"].map { type in ["assetId":"0", "oldPromotionId":type == "-8" ? "0":"", "orgId":"0", "promotionId":"0", "promotionType":type] }
                let promotions = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
                let result = try await self.post("goods/water/unlock", ["skuId":q.skuID, "promotions":promotions], epoch: epoch)
                s.orderNo = try result.required("orderNo"); try self.saveWater(s, epoch: epoch)
                _ = try await self.readWater(s, epoch: epoch)
            } catch { try self.recordWaterError(id: s.id, error: error, epoch: epoch); throw error }
        }
    }
    private func recordWaterError(id: UUID, error: Error, epoch: UUID) throws {
        try alive(epoch)
        if var current = snapshot.water, current.id == id { current.error = PGFailure.mapped(error); current.updatedAt = now(); try saveWater(current, epoch: epoch) }
    }
    private func closeWater(_ source: PGWaterSession, basis: String, epoch: UUID) throws -> PGWaterSession {
        var s = source; s.phase = "closed_unknown"; s.deviceEnded = true; s.endBasis = basis; s.remoteEnd = false; s.endedAt = s.endedAt ?? now(); s.updatedAt = now(); s.error = .waterBill
        try saveWater(s, epoch: epoch); return s
    }
    /// Read the original user's bound order only; never infer payment from the app returning to foreground.
    private func waterBill(_ source: PGWaterSession, epoch: UUID) async throws -> PGWaterSession {
        guard let number = source.orderNo else { throw PGFailure.waterUnknown }
        var s = source
        let d = try await post("order/detail", ["orderNo":number], epoch: epoch)
        let rows = try (d["tradeOrderItem"].array != nil ? d["tradeOrderItem"] : d["lineItems"]).rows()
        let id = try d.required("id")
        guard d["orderNo"].text == number, rows.count == 1, rows[0]["goodsId"].text == s.deviceID, rows[0]["skuId"].text == s.skuID,
              s.orderID == nil || s.orderID == id else { throw PGFailure.orderMismatch }
        s.orderID = id; s.amount = try PangguaiProtocol.price(d["payPrice"]); s.updatedAt = now()
        s.billPayable = d["orderStatus"].text == "0"
        if ["2", "3"].contains(d["orderStatus"].text), s.deviceEnded { s.phase = "settled"; s.error = nil }
        try saveWater(s, epoch: epoch); return s
    }
    private func optionalWaterBill(_ source: PGWaterSession, epoch: UUID) async throws -> PGWaterSession {
        do { return try await waterBill(source, epoch: epoch) }
        catch {
            try alive(epoch)
            if [.auth, .account, .orderMismatch].contains(PGFailure.mapped(error)) { throw error }
            return source
        }
    }
    func readWater(_ source: PGWaterSession, epoch: UUID) async throws -> PGWaterSession {
        var s = source
        do {
            if s.terminal || ["ended", "settling"].contains(s.phase) {
                if s.orderNo != nil { return try await optionalWaterBill(s, epoch: epoch) }
                return s
            }
            guard let number = s.orderNo else { throw PGFailure.waterUnknown }
            guard let reading = try await waterReading(skuID: s.skuID, epoch: epoch) else {
                s.emptyReads += 1
                if s.startedAt != nil, s.emptyReads >= 2 {
                    s.deviceEnded = true; s.phase = "ended"; s.endBasis = "session_closed"; s.endedAt = now(); s.error = .waterBill
                } else { s.error = .waterWait }
                s.updatedAt = now(); try saveWater(s, epoch: epoch)
                return try await optionalWaterBill(s, epoch: epoch)
            }
            s.emptyReads = 0
            guard reading["identify"].text == number else {
                let replaced = !reading["identify"].text.isEmpty
                let idle = reading["status"].text == "5" && reading["workStatus"].text == "1"
                if (s.startedAt != nil || ["using", "ending"].contains(s.phase)) && (replaced || idle) {
                    return try closeWater(s, basis: replaced ? "order_replaced":"device_idle", epoch: epoch)
                }
                s.error = .waterOwnership; s.updatedAt = now(); try saveWater(s, epoch: epoch); return s
            }
            if reading["status"].text == "5", reading["workStatus"].text == "1" {
                s.deviceEnded = true; s.endedAt = now(); s.endBasis = "device_report"; s.phase = "ended"; s.error = .waterBill
                if PangguaiProtocol.money(reading["amount"]) == "0" { s.phase = "ended_zero"; s.error = nil }
                s.updatedAt = now(); try saveWater(s, epoch: epoch)
                return try await optionalWaterBill(s, epoch: epoch)
            }
            if reading["status"].text == "1", reading["workStatus"].text == "2" {
                s.phase = s.endSent ? "ending":"using"; s.startedAt = s.startedAt ?? now(); s.error = nil
            } else { s.error = .waterWait }
            s.updatedAt = now(); try saveWater(s, epoch: epoch); return s
        } catch { try recordWaterError(id: source.id, error: error, epoch: epoch); throw error }
    }
    func endWater(confirmedSessionID: UUID) async {
        await perform { epoch in
            guard let source = self.snapshot.water, source.id == confirmedSessionID else { throw PGFailure.orderMismatch }
            var s = try await self.readWater(source, epoch: epoch)
            if s.terminal || ["ended", "settling"].contains(s.phase) || s.endSent { return }
            guard let number = s.orderNo else { throw PGFailure.waterUnknown }
            guard let reading = try await self.waterReading(skuID: s.skuID, epoch: epoch) else { throw PGFailure.waterWait }
            guard reading["identify"].text == number else { throw PGFailure.waterOwnership }
            guard reading["status"].text == "1", reading["workStatus"].text == "2" else { throw PGFailure.waterWait }
            let d = try await self.post("goods/normal/details", ["goodsId":s.deviceID], epoch: epoch)
            guard d["goodsId"].text == s.deviceID, d["categoryCode"].text == "04" else { throw PGFailure.device }
            s.remoteEnd = d["supportAppUserFinish"].yes; try self.saveWater(s, epoch: epoch)
            guard s.remoteEnd else { throw PGFailure.waterPhysicalEnd }
            s.endSent = true; s.phase = "ending"; try self.saveWater(s, epoch: epoch)
            do {
                guard try await self.post("goods/endWater", ["goodsId":s.deviceID], epoch: epoch).yes else { throw PGFailure.waterPhysicalEnd }
                _ = try await self.readWater(s, epoch: epoch)
            } catch { try self.recordWaterError(id: s.id, error: error, epoch: epoch); throw error }
        }
    }
    /// Explicit physical-stop recovery has no path to an end, create-bill or pay command.
    func confirmPhysicalWaterEnd(sessionID: UUID) async {
        await perform { epoch in
            guard let s = self.snapshot.water, s.id == sessionID else { throw PGFailure.orderMismatch }
            if s.terminal { return }
            let reading = try await self.waterReading(skuID: s.skuID, epoch: epoch)
            let basis: String
            if reading == nil { basis = "physical_confirmed" }
            else if let number = s.orderNo, !(reading?["identify"].text ?? "").isEmpty, reading?["identify"].text != number { basis = "order_replaced" }
            else if reading?["status"].text == "5", reading?["workStatus"].text == "1" { basis = "device_idle" }
            else { throw reading?["identify"].text == s.orderNo ? PGFailure.waterStillActive : PGFailure.waterWait }
            _ = try self.closeWater(s, basis: basis, epoch: epoch)
        }
    }
    /// A separate, user-requested bill review precedes settlement. Polling never calls this method.
    func prepareWaterSettlement(sessionID: UUID) async {
        await perform { epoch in
            self.settlementQuote = nil
            guard let source = self.snapshot.water, source.id == sessionID else { throw PGFailure.orderMismatch }
            var s = try await self.readWater(source, epoch: epoch)
            guard s.deviceEnded, ["ended", "settling"].contains(s.phase), let number = s.orderNo, !s.settleSent else { throw PGFailure.waterBill }
            if !s.afterPaySent {
                s.afterPaySent = true; try self.saveWater(s, epoch: epoch)
                let created = try await self.post("order/afterPay/creating", ["orderNo":number], epoch: epoch)
                guard created["orderNo"].text == number else { throw PGFailure.orderMismatch }
                s.orderID = try created.required("orderId"); try self.saveWater(s, epoch: epoch)
            }
            s = try await self.waterBill(s, epoch: epoch)
            if s.phase == "settled" { return }
            guard s.billPayable, let amount = s.amount else { throw PGFailure.price }
            self.settlementQuote = PGWaterSettlement(sessionID: s.id, expiresAt: self.now().addingTimeInterval(60), amount: amount, deviceName: s.deviceName, paymentName: s.paymentName)
        }
    }
    func settleWater(confirmedQuoteID: UUID) async {
        await perform { epoch in
            guard let q = self.settlementQuote, q.id == confirmedQuoteID, self.now() <= q.expiresAt else { throw PGFailure.quoteExpired }
            self.settlementQuote = nil
            guard let source = self.snapshot.water, source.id == q.sessionID, source.deviceEnded, !source.settleSent, let number = source.orderNo else { throw PGFailure.orderMismatch }
            var s = try await self.waterBill(source, epoch: epoch)
            if s.phase == "settled" { return }
            guard s.billPayable, s.amount == q.amount else { throw PGFailure.priceChanged }
            s.settleSent = true; s.phase = "settling"; try self.saveWater(s, epoch: epoch)
            do {
                let result = try await self.post("order/sync", ["orderNo":number, "payType":"0"], epoch: epoch)
                guard result["code"].text == "0" else { throw PGFailure.waterBill }
                _ = try await self.waterBill(s, epoch: epoch)
            } catch { try self.recordWaterError(id: s.id, error: error, epoch: epoch); throw error }
        }
    }
}
