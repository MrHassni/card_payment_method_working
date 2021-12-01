import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:square_in_app_payments/in_app_payments.dart';
import 'package:square_in_app_payments/google_pay_constants.dart'
as google_pay_constants;
import 'colors.dart';
import 'config.dart';
import 'widgets/buy_sheet.dart';

void main() => runApp(const MaterialApp(
  title: 'Super Cookie',
  home: HomeScreen(),
));

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  bool isLoading = true;
  bool googlePayEnabled = false;

  static final GlobalKey<ScaffoldState> scaffoldKey =
  GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initSquarePayment();

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _initSquarePayment() async {
    await InAppPayments.setSquareApplicationId(squareApplicationId);

    var canUseGooglePay = false;
    if (Platform.isAndroid) {
      await InAppPayments.initializeGooglePay(
          squareLocationId, google_pay_constants.environmentTest);
      canUseGooglePay = await InAppPayments.canUseGooglePay;
      canUseGooglePay = true;
    }

    setState(() {
      isLoading = false;
      googlePayEnabled = canUseGooglePay;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
      theme: ThemeData(canvasColor: Colors.white),
      home: Scaffold(
          body: isLoading
              ? Center(
              child: CircularProgressIndicator(
                valueColor:
                AlwaysStoppedAnimation<Color>(mainBackgroundColor),
              ))
              : BuySheet(
              googlePayEnabled: googlePayEnabled,
              squareLocationId: squareLocationId)));
}