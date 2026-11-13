import XCTest
@testable import GripCore

/// Vectors generated with the official hyperliquid-python-sdk (signing.sign_l1_action)
/// using a throwaway test key. If these pass, Grip signs exactly like the official SDK.
final class SigningTests: XCTestCase {
    let key = "0x0123456789012345678901234567890123456789012345678901234567890123"
    let nonce: UInt64 = 1794604464174
    let btc = AssetInfo(name: "BTC", index: 0, szDecimals: 5, maxLeverage: 40)

    func testKeccak() {
        XCTAssertEqual(Keccak.hash256(Data()).hex, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        XCTAssertEqual(Keccak.hash256(Data("abc".utf8)).hex, "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        // Multi-block input (> 136 bytes)
        let long = Data(repeating: 0x61, count: 300)
        XCTAssertEqual(Keccak.hash256(long).count, 32)
    }

    func testAddressDerivation() throws {
        let signer = try EthSigner(privateKeyHex: key)
        XCTAssertEqual(signer.address, "0x14791697260E4c9A71f18484C9f997B308e59325")
    }

    func testFloatToWire() {
        XCTAssertEqual(HLFormat.wire(97250.0), "97250")
        XCTAssertEqual(HLFormat.wire(0.001), "0.001")
        XCTAssertEqual(HLFormat.wire(1.25), "1.25")
        XCTAssertEqual(HLFormat.wire(96750.5), "96750.5")
        XCTAssertEqual(HLFormat.wire(1e-8), "0.00000001")
        XCTAssertEqual(HLFormat.wire(0), "0")
    }

    private func sampleAction() -> WireValue {
        HLActions.order([
            OrderRequest(asset: btc, isBuy: true, size: 1.25, limitPx: 96950, reduceOnly: false, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: false, size: 1.25, limitPx: 98400, reduceOnly: true, kind: .trigger(triggerPx: 98400, isMarket: true, tpsl: .tp)),
            OrderRequest(asset: btc, isBuy: false, size: 0.00123, limitPx: 96751, reduceOnly: true, kind: .trigger(triggerPx: 96751, isMarket: true, tpsl: .sl)),
        ], grouping: "normalTpsl")
    }

    func testOrderActionEncoding() {
        let action = sampleAction()
        XCTAssertEqual(action.json(), #"{"type":"order","orders":[{"a":0,"b":true,"p":"96950","s":"1.25","r":false,"t":{"limit":{"tif":"Gtc"}}},{"a":0,"b":false,"p":"98400","s":"1.25","r":true,"t":{"trigger":{"isMarket":true,"triggerPx":"98400","tpsl":"tp"}}},{"a":0,"b":false,"p":"96751","s":"0.00123","r":true,"t":{"trigger":{"isMarket":true,"triggerPx":"96751","tpsl":"sl"}}}],"grouping":"normalTpsl"}"#)
        XCTAssertEqual(action.msgpack().hex, "83a474797065a56f72646572a66f72646572739386a16100a162c3a170a53936393530a173a4312e3235a172c2a17481a56c696d697481a3746966a347746386a16100a162c2a170a53938343030a173a4312e3235a172c3a17481a77472696767657283a869734d61726b6574c3a9747269676765725078a53938343030a47470736ca2747086a16100a162c2a170a53936373531a173a7302e3030313233a172c3a17481a77472696767657283a869734d61726b6574c3a9747269676765725078a53936373531a47470736ca2736ca867726f7570696e67aa6e6f726d616c5470736c")
        XCTAssertEqual(HLSigning.actionHash(action: action, nonce: nonce).hex, "4572cf14cc83dad33574d34e78c7cac2b48f3a091461714ca747cccfd816134b")
    }

    func testOrderSignatureMainnetAndTestnet() throws {
        let signer = try EthSigner(privateKeyHex: key)
        let main = try HLSigning.signL1Action(sampleAction(), nonce: nonce, isMainnet: true, signer: signer)
        XCTAssertEqual("0x" + main.r.hex, "0xbb9d6a5337b6b97f0be750920daacf9a0c61787ac5209b5b094d4a81c7328ede")
        XCTAssertEqual("0x" + main.s.hex, "0x7dabc83d3802558ba85a86b29d5139f925bfe6d9db47d515937426d80e7b5fbb")
        XCTAssertEqual(main.v, 28)
        let test = try HLSigning.signL1Action(sampleAction(), nonce: nonce, isMainnet: false, signer: signer)
        XCTAssertEqual("0x" + test.r.hex, "0x2cd512b14e02a7768a4cfcce1812f51a5c55b31b90b1db8f04a2eb805dad8f68")
        XCTAssertEqual("0x" + test.s.hex, "0x45cada2b19ee0847d66809190a9920664d0d7710c64f61a826b561d99c5af9d2")
        XCTAssertEqual(test.v, 28)
    }

    func testLeverageAndCancelSignatures() throws {
        let signer = try EthSigner(privateKeyHex: key)
        let lev = try HLSigning.signL1Action(HLActions.updateLeverage(asset: 3, isCross: true, leverage: 7), nonce: nonce, isMainnet: false, signer: signer)
        XCTAssertEqual("0x" + lev.r.hex, "0xe490de558bf2cde0701bf04fc359beb37fef7ba376d64bd4cdf144ab21926dbd")
        XCTAssertEqual("0x" + lev.s.hex, "0x2f02d1c4554fe2a9b71683aa2cb7c21925d970419bcf8d0b3047a6c60074fb29")
        XCTAssertEqual(lev.v, 27)
        let cancel = try HLSigning.signL1Action(HLActions.cancel(asset: 0, oid: 123456789012), nonce: nonce + 1, isMainnet: true, signer: signer)
        XCTAssertEqual("0x" + cancel.r.hex, "0xafe632726eb94779e298ba6146b970e0d63b66f356f178365d0c233b8da424f1")
        XCTAssertEqual("0x" + cancel.s.hex, "0x7ff4f7ea509c9abcfdf0e34de66bca0fb4804f00cf4e2bd4b8eda2d44efe4374")
        XCTAssertEqual(cancel.v, 28)
    }

    func testInvalidKeyRejected() {
        XCTAssertThrowsError(try EthSigner(privateKeyHex: "0x1234"))
        XCTAssertThrowsError(try EthSigner(privateKeyHex: String(repeating: "0", count: 64)))
    }
}
