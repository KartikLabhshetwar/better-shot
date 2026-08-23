import CryptoKit
import Foundation

enum R2SigV4Reference {
    static func hmac(key: SymmetricKey, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
    }

    static func hmacHex(key: SymmetricKey, message: String) -> String {
        hmac(key: key, message: message).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func deriveSigningKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let kSecret = SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8))
        let kDate = hmac(key: kSecret, message: dateStamp)
        let kRegion = hmac(key: SymmetricKey(data: kDate), message: region)
        let kService = hmac(key: SymmetricKey(data: kRegion), message: service)
        return SymmetricKey(data: hmac(key: SymmetricKey(data: kService), message: "aws4_request"))
    }

    private static let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    static func uriEncodePath(_ path: String) -> String {
        var encoded = ""
        for scalar in path.unicodeScalars {
            if unreservedCharacters.contains(scalar) {
                encoded.unicodeScalars.append(scalar)
            } else if scalar == "/" {
                encoded += "/"
            } else {
                for byte in String(scalar).utf8 {
                    encoded += String(format: "%%%02X", byte)
                }
            }
        }
        return encoded
    }
}

func checkAWSOfficialGetObjectVector() {
    let canonicalRequest = [
        "GET",
        "/test.txt",
        "",
        "host:examplebucket.s3.amazonaws.com\nrange:bytes=0-9\nx-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nx-amz-date:20130524T000000Z\n",
        "host;range;x-amz-content-sha256;x-amz-date",
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    ].joined(separator: "\n")

    let canonicalRequestHash = R2SigV4Reference.sha256Hex(canonicalRequest)
    assert(canonicalRequestHash == "7344ae5b7ee6c3e7e6b0fe0640412a37625d1fbfff95c48bbb2dc43964946972", "canonical request hash mismatch")

    let stringToSign = [
        "AWS4-HMAC-SHA256",
        "20130524T000000Z",
        "20130524/us-east-1/s3/aws4_request",
        canonicalRequestHash,
    ].joined(separator: "\n")

    let signingKey = R2SigV4Reference.deriveSigningKey(
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLE",
        dateStamp: "20130524",
        region: "us-east-1",
        service: "s3"
    )
    let signingKeyHex = signingKey.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    assert(signingKeyHex == "db833e0f5e435b208142db4786ec9153e01cc2cde3b2f7ec5083d8810df17b14", "signing key mismatch")

    let signature = R2SigV4Reference.hmacHex(key: signingKey, message: stringToSign)
    assert(signature == "35788a3fc1643e1b1ea7f1e67b4fde26dbfef66fd5d75519c81e5914c5ce2003", "final signature mismatch")

    print("PASS: AWS official GET Object SigV4 test vector")
}

func checkR2UploadStyleVector() {
    let host = "test-account.r2.cloudflarestorage.com"
    let canonicalURI = R2SigV4Reference.uriEncodePath("/mybucket/recordings/abc-123/My File (final).mp4")
    assert(canonicalURI == "/mybucket/recordings/abc-123/My%20File%20%28final%29.mp4", "URI encoding mismatch")

    let amzDate = "20240115T103000Z"
    let dateStamp = "20240115"
    let payloadHash = "UNSIGNED-PAYLOAD"
    let contentType = "video/quicktime"

    let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
    let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

    let canonicalRequest = [
        "PUT",
        canonicalURI,
        "",
        canonicalHeaders,
        signedHeaders,
        payloadHash,
    ].joined(separator: "\n")

    let canonicalRequestHash = R2SigV4Reference.sha256Hex(canonicalRequest)
    assert(canonicalRequestHash == "f18c02b93583dc0258fe2eb799e4a8957d134aaf61c6f39fb6e94bcd9e606051", "canonical request hash mismatch")

    let credentialScope = "\(dateStamp)/auto/s3/aws4_request"
    let stringToSign = [
        "AWS4-HMAC-SHA256",
        amzDate,
        credentialScope,
        canonicalRequestHash,
    ].joined(separator: "\n")

    let signingKey = R2SigV4Reference.deriveSigningKey(
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLE",
        dateStamp: dateStamp,
        region: "auto",
        service: "s3"
    )
    let signingKeyHex = signingKey.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    assert(signingKeyHex == "5a9eda12430c696b70e82fb9774d9d09a92532fb81e1bf096c22eec47cc6b2fc", "signing key mismatch")

    let signature = R2SigV4Reference.hmacHex(key: signingKey, message: stringToSign)
    assert(signature == "91c4717ab69ef61db3fe119f890325d5c7ce8c19f0c8df7b4e85521e70214491", "final signature mismatch")

    let authorizationHeader = "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    assert(authorizationHeader == "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20240115/auto/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=91c4717ab69ef61db3fe119f890325d5c7ce8c19f0c8df7b4e85521e70214491", "authorization header mismatch")

    print("PASS: R2 upload-style SigV4 vector (UNSIGNED-PAYLOAD, region=auto)")
}

checkAWSOfficialGetObjectVector()
checkR2UploadStyleVector()
print("All R2 SigV4 checks passed.")
