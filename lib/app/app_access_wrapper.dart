import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_models.dart'; // Add this import
import '../services/iap_simulation_service.dart';
import '../screens/daily_podcast_screen.dart';
import '../screens/subscription_screen.dart';

class AppAccessWrapper extends StatefulWidget {
  @override
  _AppAccessWrapperState createState() => _AppAccessWrapperState();
}

class _AppAccessWrapperState extends State<AppAccessWrapper> {
  @override
  Widget build(BuildContext context) {
    final iapService = Provider.of<IAPSimulationService>(context);

    return FutureBuilder<AppAccessState>(
      future: iapService.getAccessState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(
                    'Checking access...',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final accessState = snapshot.data ?? AppAccessState.trialExpired;

        switch (accessState) {
          case AppAccessState.hasAccess:
            return DailyPodcastScreen();
          case AppAccessState.inTrial:
            return DailyPodcastScreen(
              showTrialBanner: true,
              daysRemaining: iapService.daysRemaining,
            );
          case AppAccessState.trialExpired:
            return SubscriptionScreen();
          default:
            return SubscriptionScreen();
        }
      },
    );
  }
}
