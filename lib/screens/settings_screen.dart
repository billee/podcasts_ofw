import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/iap_simulation_service.dart';
import '../models/app_models.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final iapService = Provider.of<IAPSimulationService>(context);

    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.workspace_premium),
            title: Text('Subscription'),
            subtitle: FutureBuilder<AppAccessState>(
              future: iapService.getAccessState(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final state = snapshot.data!;
                  return Text(state == AppAccessState.hasAccess
                      ? 'Active Subscription'
                      : state == AppAccessState.inTrial
                          ? 'Free Trial Active'
                          : 'No Active Subscription');
                }
                return Text('Checking status...');
              },
            ),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => SubscriptionScreen())),
          ),
          ListTile(
            leading: Icon(Icons.restore),
            title: Text('Restore Purchases'),
            onTap: () => iapService.simulateRestorePurchases(),
          ),
          ListTile(
            leading: Icon(Icons.cloud),
            title: Text('Check Firebase Connection'),
            onTap: () => iapService.debugCheckFirebaseConnection(),
          ),
          ListTile(
            leading: Icon(Icons.help),
            title: Text('Help & Support'),
            onTap: () => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Help & Support'),
                content: Text(
                    'For subscription issues, please contact support@yourapp.com'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('OK'))
                ],
              ),
            ),
          ),
          // Debug section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('DEBUG',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: Icon(Icons.bug_report),
            title: Text('Debug State'),
            onTap: () => iapService.debugPrintState(),
          ),
          ListTile(
            leading: Icon(Icons.refresh),
            title: Text('Reset Trial to Day 1'),
            onTap: () async {
              await iapService.debugResetTrial();
              // Just pop back to the previous screen
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.warning),
            title: Text('Set Trial to Last Day'),
            onTap: () async {
              await iapService.debugSetTrialToLastDay();
              // Just pop back to the previous screen
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.error),
            title: Text('Set Trial Expired'),
            onTap: () async {
              await iapService.debugSetTrialExpired();
              // Just pop back to the previous screen
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Updating trial...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
