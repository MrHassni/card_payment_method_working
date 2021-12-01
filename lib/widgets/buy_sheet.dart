import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:square_in_app_payments/models.dart';
import 'package:square_in_app_payments/in_app_payments.dart';
import 'package:square_in_app_payments/google_pay_constants.dart'
as google_pay_constants;
import '../colors.dart';
import '../config.dart';
import '../transaction_service.dart';
import 'dialog_model.dart';
import 'model_bottom_sheet.dart' as custom_modal_bottom_sheet;
import 'order_sheet.dart';


class BuySheet extends StatefulWidget {
  final bool? googlePayEnabled;
  final String? squareLocationId;
  static final GlobalKey<ScaffoldState> scaffoldKey =
  GlobalKey<ScaffoldState>();

  const BuySheet(
      {Key? key ,
        this.googlePayEnabled,
        this.squareLocationId}) : super(key: key);

  @override
  BuySheetState createState() => BuySheetState();
}

class BuySheetState extends State<BuySheet> {

  bool get _chargeServerHostReplaced => chargeServerHost != "REPLACE_ME";

  bool get _squareLocationSet => widget.squareLocationId != "REPLACE_ME";


  void _showOrderSheet() async {
    var selection =
    await custom_modal_bottom_sheet.showModalBottomSheet<PaymentType>(
        context: BuySheet.scaffoldKey.currentState!.context,
        builder: (context) => OrderSheet(
          googlePayEnabled: widget.googlePayEnabled!,
        ));

    switch (selection) {
      case PaymentType.cardPayment:
      // call _onStartCardEntryFlow to start Card Entry without buyer verification (SCA)
        await _onStartCardEntryFlow();
        // OR call _onStartCardEntryFlowWithBuyerVerification to start Card Entry with buyer verification (SCA)
        // NOTE this requires _squareLocationSet to be set
        // await _onStartCardEntryFlowWithBuyerVerification();
        break;
      case PaymentType.googlePay:
        if (_squareLocationSet && widget.googlePayEnabled!) {
          _onStartGooglePay();
        } else {
          _showSquareLocationIdNotSet();
        }
        break;
    }
  }

  void printCurlCommand(String nonce, String? verificationToken) {
    var hostUrl = 'https://connect.squareup.com';
    if (squareApplicationId.startsWith('sandbox')) {
      hostUrl = 'https://connect.squareupsandbox.com';
    }
    var uuid = const Uuid().v4();

    if (verificationToken == null) {
      print(
          'curl --request POST $hostUrl/v2/payments \\'
              '--header \"Content-Type: application/json\" \\'
              '--header \"Authorization: Bearer YOUR_ACCESS_TOKEN\" \\'
              '--header \"Accept: application/json\" \\'
              '--data \'{'
              '\"idempotency_key\": \"$uuid\",'
              '\"amount_money\": {'
              '\"amount\": $cookieAmount,'
              '\"currency\": \"USD\"},'
              '\"source_id\": \"$nonce\"'
              '}\'');
    } else {
      print('curl --request POST $hostUrl/v2/payments \\'
          '--header \"Content-Type: application/json\" \\'
          '--header \"Authorization: Bearer YOUR_ACCESS_TOKEN\" \\'
          '--header \"Accept: application/json\" \\'
          '--data \'{'
          '\"idempotency_key\": \"$uuid\",'
          '\"amount_money\": {'
          '\"amount\": $cookieAmount,'
          '\"currency\": \"USD\"},'
          '\"source_id\": \"$nonce\",'
          '\"verification_token\": \"$verificationToken\"'
          '}\'');
    }
  }

  void _showUrlNotSetAndPrintCurlCommand(String nonce,
      {String? verificationToken}) {
    String title;
    if (verificationToken != null) {
      title = "Nonce and verification token generated but not charged";
    } else {
      title = "Nonce generated but not charged";
    }
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: title,
        description:
        "Check your console for a CURL command to charge the nonce, or replace CHARGE_SERVER_HOST with your server host.");
    printCurlCommand(nonce, verificationToken);
  }

  void _showSquareLocationIdNotSet() {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Missing Square Location ID",
        description:
        "To request a Google Pay nonce, replace squareLocationId in main.dart with a Square Location ID.");
  }

  void _onCardEntryComplete() {
    if (_chargeServerHostReplaced) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Your order was successful",
          description:
          "Go to your Square dashboard to see this order reflected in the sales tab.");
    }
  }

  void _onCardEntryCardNonceRequestSuccess(CardDetails result) async {
    if (!_chargeServerHostReplaced) {
      InAppPayments.completeCardEntry(
          onCardEntryComplete: _onCardEntryComplete);
      _showUrlNotSetAndPrintCurlCommand(result.nonce);
      return;
    }
    try {
      await chargeCard(result);
      InAppPayments.completeCardEntry(
          onCardEntryComplete: _onCardEntryComplete);
    } on ChargeException catch (ex) {
      InAppPayments.showCardNonceProcessingError(ex.errorMessage);
    }
  }

  Future<void> _onStartCardEntryFlow() async {
    await InAppPayments.startCardEntryFlow(
        onCardNonceRequestSuccess: _onCardEntryCardNonceRequestSuccess,
        onCardEntryCancel: _onCancelCardEntryFlow,
        collectPostalCode: true);
  }


  // Future<void> _onStartCardEntryFlowWithBuyerVerification() async {
  //   var money = Money((b) => b
  //     ..amount = 100
  //     ..currencyCode = 'USD');
  //
  //   var contact = Contact((b) => b
  //     ..givenName = "John"
  //     ..familyName = "Doe"
  //     ..addressLines =
  //     BuiltList<String>(["London Eye", "Riverside Walk"]).toBuilder()
  //     ..city = "London"
  //     ..countryCode = "GB"
  //     ..email = "johndoe@example.com"
  //     ..phone = "8001234567"
  //     ..postalCode = "SE1 7");
  //
  //   await InAppPayments.startCardEntryFlowWithBuyerVerification(
  //       onBuyerVerificationSuccess: _onBuyerVerificationSuccess,
  //       onBuyerVerificationFailure: _onBuyerVerificationFailure,
  //       onCardEntryCancel: _onCancelCardEntryFlow,
  //       buyerAction: "Charge",
  //       money: money,
  //       squareLocationId: squareLocationId,
  //       contact: contact,
  //       collectPostalCode: true);
  // }

  void _onCancelCardEntryFlow() {
    _showOrderSheet();
  }

  void _onStartGooglePay() async {
    try {
      await InAppPayments.requestGooglePayNonce(
          priceStatus: google_pay_constants.totalPriceStatusFinal,
          price: getCookieAmount(),
          currencyCode: 'USD',
          onGooglePayNonceRequestSuccess: _onGooglePayNonceRequestSuccess,
          onGooglePayNonceRequestFailure: _onGooglePayNonceRequestFailure,
          onGooglePayCanceled: onGooglePayEntryCanceled);
    } on PlatformException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Failed to start GooglePay",
          description: ex.toString());
    }
  }

  void _onGooglePayNonceRequestSuccess(CardDetails result) async {
    if (!_chargeServerHostReplaced) {
      _showUrlNotSetAndPrintCurlCommand(result.nonce);
      return;
    }
    try {
      await chargeCard(result);
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Your order was successful",
          description:
          "Go to your Square dashboard to see this order reflected in the sales tab.");
    } on ChargeException catch (ex) {
      showAlertDialog(
          context: BuySheet.scaffoldKey.currentContext!,
          title: "Error processing GooglePay payment",
          description: ex.errorMessage);
    }
  }

  void _onGooglePayNonceRequestFailure(ErrorInfo errorInfo) {
    showAlertDialog(
        context: BuySheet.scaffoldKey.currentContext!,
        title: "Failed to request GooglePay nonce",
        description: errorInfo.toString());
  }

  void onGooglePayEntryCanceled() {
    _showOrderSheet();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(canvasColor: Colors.transparent),
    home: Scaffold(
      backgroundColor: mainBackgroundColor,
      key: BuySheet.scaffoldKey,
      body: Builder(
        builder: (context) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Image(image: AssetImage("assets/iconCookie.png")),
                const Text(
                  'Super Cookie',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ),
                const Text(
                  "Instantly gain special powers \nwhen ordering a super cookie",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 32),
                  child: ElevatedButton(onPressed: _showOrderSheet,child: const Text('Buy')),
                ),
              ],
            )),
      ),
    ),
  );
}
