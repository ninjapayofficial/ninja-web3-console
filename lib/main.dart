import 'package:flutter/material.dart';
import 'contract_interface_page.dart';

void main() {
  runApp(NinjaPayApp());
}

class NinjaPayApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NinjaPay Contract Interface',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ContractInterfacePage(),
    );
  }
}
