# Apple trust roots

These public DER certificates come from Apple's PKI page:
https://www.apple.com/certificateauthority/

- https://www.apple.com/certificateauthority/AppleRootCA-G2.cer
- https://www.apple.com/certificateauthority/AppleRootCA-G3.cer

They are trust anchors for Apple's official App Store Server Library, not private
signing material. Keep them in the deployed functions bundle. Never substitute
certificates supplied by a request. Review updates when upgrading the library.
