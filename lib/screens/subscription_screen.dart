import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/iap_simulation_service.dart';
import '../app/global_context.dart'; // Add this import

class SubscriptionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Set the global context for IAP service
    GlobalContext.context = context;

    final iapService = Provider.of<IAPSimulationService>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header
              Icon(Icons.workspace_premium, size: 80, color: Colors.blue),
              SizedBox(height: 16),
              Text('Unlock Full Access',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text(
                  'Your 7-day free trial has ended. Subscribe to continue enjoying daily podcasts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5)),
              SizedBox(height: 24),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildFeatureList(),
                      SizedBox(height: 24),
                      _buildPricingCard(),
                    ],
                  ),
                ),
              ),

              // Fixed buttons
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => iapService.simulatePurchase(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Subscribe Now - \$4.99/month',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              SizedBox(height: 12),
              TextButton(
                onPressed: () => iapService.simulateRestorePurchases(),
                child: Text('Restore Purchase',
                    style: TextStyle(color: Colors.blue)),
              ),
              // Debug button
              TextButton(
                onPressed: () => iapService.debugResetTrial(),
                child: Text('DEBUG: Reset Trial',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    final features = [
      'Daily podcast episodes',
      'High-quality audio',
      'Offline listening',
      'No advertisements',
      'Exclusive content',
      'Cancel anytime',
    ];

    return Column(
      children: features
          .map((feature) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text(feature, style: TextStyle(fontSize: 16))),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildPricingCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Monthly Subscription',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('\$4.99 / month',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue)),
            SizedBox(height: 8),
            Text('Auto-renews monthly',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
