/// Hand-written Magento 2.4.8 auth operations (codegen migration is Phase 1.x).
abstract final class AuthQueries {
  static const String generateToken = r'''
mutation GenerateToken($email: String!, $password: String!) {
  generateCustomerToken(email: $email, password: $password) {
    token
  }
}
''';

  static const String createCustomer = r'''
mutation CreateCustomer($input: CustomerCreateInput!) {
  createCustomerV2(input: $input) {
    customer {
      firstname
      lastname
      email
    }
  }
}
''';

  static const String revokeToken = r'''
mutation RevokeToken {
  revokeCustomerToken {
    result
  }
}
''';

  /// Permanently deletes the authenticated customer. Required by App Store
  /// Review Guideline 5.1.1(v) — an app that creates accounts must let the
  /// customer delete one from inside the app. Scoped by the bearer token, so
  /// it takes no arguments.
  static const String deleteCustomer = r'''
mutation DeleteCustomer {
  deleteCustomer
}
''';

  static const String requestPasswordReset = r'''
mutation RequestPasswordReset($email: String!) {
  requestPasswordResetEmail(email: $email)
}
''';

  static const String resetPassword = r'''
mutation ResetPassword(
  $email: String!
  $resetPasswordToken: String!
  $newPassword: String!
) {
  resetPassword(
    email: $email
    resetPasswordToken: $resetPasswordToken
    newPassword: $newPassword
  )
}
''';

  static const String customer = r'''
query CurrentCustomer {
  customer {
    firstname
    lastname
    email
    avatar_url
    custom_attributes {
      code
      ... on AttributeValue { value }
    }
  }
}
''';
}
