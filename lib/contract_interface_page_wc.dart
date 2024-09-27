// lib/contract_interface_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/crypto.dart';
import 'dart:convert';
import 'package:web3dart/web3dart.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

class ContractInterfacePage extends StatefulWidget {
  @override
  _ContractInterfacePageState createState() => _ContractInterfacePageState();
}

class _ContractInterfacePageState extends State<ContractInterfacePage> {
  // Controllers for input fields
  TextEditingController _contractAddressController = TextEditingController();

  String _walletAddress = '';
  bool _walletConnected = false;

  String _contractAddress = '';
  bool _contractLoaded = false;
  List<dynamic> _abi = [];
  List<ContractFunction> _readFunctions = [];
  List<ContractFunction> _writeFunctions = [];

  DeployedContract? _deployedContract;
  ContractFunction? _selectedFunction;
  List<TextEditingController> _paramControllers = [];

  String _result = '';

  late Web3Client _client;

  // WalletConnect variables
  WalletConnect? _connector;
  SessionStatus? _session;
  String? _walletConnectUri;

  @override
  void initState() {
    super.initState();
    // Replace with your Ethereum node URL (Infura)
    String rpcUrl = 'https://sepolia.infura.io/v3/5e5afd85b4aa4e7ab3719e32e9eee3a2';
    _client = Web3Client(rpcUrl, http.Client());

    _connector = WalletConnect(
      bridge: 'https://bridge.walletconnect.org',
      clientMeta: const PeerMeta(
        name: 'NinjaPay',
        description: 'NinjaPay WalletConnect Integration',
        url: 'https://ninjapay.in',
        icons: [
          'https://ninjapay.in/icon.png',
        ],
      ),
    );

    _connector!.on('connect', (session) {
      setState(() {
        _session = session as SessionStatus;
        _walletAddress = _session!.accounts[0];
        _walletConnected = true;
        _walletConnectUri = null;
      });
    });

    _connector!.on('disconnect', (payload) {
      _disconnectWallet();
    });
  }

  @override
  void dispose() {
    _contractAddressController.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _connectWallet() async {
    if (!_connector!.connected) {
      try {
        _session = await _connector!.createSession(
          chainId: 11155111, // Sepolia chain ID
          onDisplayUri: (uri) async {
            // For mobile, use deep linking
            if (await canLaunch(uri)) {
              await launch(uri);
            } else {
              // For desktop/web, display QR code
              setState(() {
                _walletConnectUri = uri;
              });
            }
          },
        );
      } catch (e) {
        print('Error connecting wallet: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect wallet')),
        );
      }
    }
  }

  void _disconnectWallet() {
    if (_connector != null && _connector!.connected) {
      _connector!.killSession();
      setState(() {
        _walletConnected = false;
        _walletAddress = '';
      });
    }
  }

  Future<void> _loadContract() async {
    String contractAddress = _contractAddressController.text.trim();
    if (contractAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a contract address')),
      );
      return;
    }

    // Fetch ABI from Etherscan
    String apiKey = 'TZU9YP9Y15NI9W9TYHV6NGFZ78IVBKJ1WZ';
    String url =
        'https://api-sepolia.etherscan.io/api?module=contract&action=getabi&address=$contractAddress&apikey=$apiKey';

    try {
      var response = await http.get(Uri.parse(url));
      var data = jsonDecode(response.body);
      if (data['status'] != '1') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch ABI')),
        );
        return;
      }
      String abiString = data['result'];
      List<dynamic> abiJson = jsonDecode(abiString);

      // Parse ABI and get functions
      DeployedContract contract = DeployedContract(
        ContractAbi.fromJson(abiString, 'NinjaPayContract'),
        EthereumAddress.fromHex(contractAddress),
      );

      List<ContractFunction> functions = contract.functions;

      // Separate read and write functions
      List<ContractFunction> readFunctions = [];
      List<ContractFunction> writeFunctions = [];
      for (var func in functions) {
        if (func.isConstant) {
          readFunctions.add(func);
        } else {
          writeFunctions.add(func);
        }
      }

      setState(() {
        _contractAddress = contractAddress;
        _abi = abiJson;
        _deployedContract = contract;
        _readFunctions = readFunctions;
        _writeFunctions = writeFunctions;
        _contractLoaded = true;
        _selectedFunction = null;
        _paramControllers = [];
        _result = '';
      });
    } catch (e) {
      print('Error loading contract: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading contract')),
      );
    }
  }

  void _selectFunction(ContractFunction function) {
    List<TextEditingController> controllers = [];
    for (var param in function.parameters) {
      controllers.add(TextEditingController());
    }
    setState(() {
      _selectedFunction = function;
      _paramControllers = controllers;
      _result = '';
    });
  }

  Future<void> _callFunction() async {
    if (_selectedFunction == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a function')),
      );
      return;
    }

    List<dynamic> params = [];
    for (int i = 0; i < _paramControllers.length; i++) {
      String value = _paramControllers[i].text.trim();
      String typeName = _selectedFunction!.parameters[i].type.name;

      dynamic parsedValue;
      try {
        if (typeName == 'address') {
          parsedValue = EthereumAddress.fromHex(value);
        } else if (typeName.startsWith('uint') || typeName.startsWith('int')) {
          parsedValue = BigInt.parse(value);
        } else if (typeName == 'bool') {
          parsedValue = value.toLowerCase() == 'true';
        } else if (typeName == 'string') {
          parsedValue = value;
        } else if (typeName.startsWith('uint[') ||
            typeName.startsWith('int[')) {
          // Handle arrays of integers
          parsedValue =
              value.split(',').map((s) => BigInt.parse(s.trim())).toList();
        } else {
          // Other types
          parsedValue = value;
        }
        params.add(parsedValue);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid parameter: $value')),
        );
        return;
      }
    }

    try {
      if (_selectedFunction!.isConstant) {
        // Read function
        var result = await _client.call(
          contract: _deployedContract!,
          function: _selectedFunction!,
          params: params,
        );
        setState(() {
          _result = result.toString();
        });
      } else {
        // Write function
        if (!_walletConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please connect your wallet')),
          );
          return;
        }

        // Create the transaction data
        final transaction = Transaction.callContract(
          contract: _deployedContract!,
          function: _selectedFunction!,
          parameters: params,
          // Specify gas and value if needed
        );

        // Encode the transaction data
        final txData = await transaction.data;

        // Create the transaction payload
        final txPayload = {
          'from': _walletAddress,
          'to': _contractAddress,
          'data': bytesToHex(txData!, include0x: true),
          'gas': '0x5208', // Adjust gas limit as needed
          // Include 'value' if sending Ether
        };

        // Send transaction using WalletConnect
        final txHash = await _connector!.sendCustomRequest(
          method: 'eth_sendTransaction',
          params: [txPayload],
        );

        setState(() {
          _result = 'Transaction hash: $txHash';
        });
      }
    } catch (e) {
      print('Error sending transaction: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending transaction')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('NinjaPay Contract Interface'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _contractAddressController,
              decoration: InputDecoration(
                labelText: 'Contract Address',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _loadContract,
              child: Text('Load Contract'),
            ),
            SizedBox(height: 20),
            if (_contractLoaded) ...[
              Text('Functions', style: TextStyle(fontSize: 18)),
              SizedBox(height: 10),
              DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: 'Read'),
                        Tab(text: 'Write'),
                      ],
                    ),
                    SizedBox(
                      height: 300,
                      child: TabBarView(
                        children: [
                          // Read functions
                          ListView.builder(
                            itemCount: _readFunctions.length,
                            itemBuilder: (context, index) {
                              ContractFunction func = _readFunctions[index];
                              return ListTile(
                                title: Text(func.name),
                                onTap: () => _selectFunction(func),
                              );
                            },
                          ),
                          // Write functions
                          ListView.builder(
                            itemCount: _writeFunctions.length,
                            itemBuilder: (context, index) {
                              ContractFunction func = _writeFunctions[index];
                              return ListTile(
                                title: Text(func.name),
                                onTap: () => _selectFunction(func),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 20),
            if (_selectedFunction != null) ...[
              Text('Selected Function: ${_selectedFunction!.name}',
                  style: TextStyle(fontSize: 18)),
              SizedBox(height: 10),
              Column(
                children: List.generate(_paramControllers.length, (index) {
                  return TextField(
                    controller: _paramControllers[index],
                    decoration: InputDecoration(
                      labelText:
                          '${_selectedFunction!.parameters[index].name} (${_selectedFunction!.parameters[index].type})',
                      border: OutlineInputBorder(),
                    ),
                  );
                }),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: _callFunction,
                child: Text('Call Function'),
              ),
              SizedBox(height: 10),
            ],
            if (_result.isNotEmpty) ...[
              Text('Result:', style: TextStyle(fontSize: 18)),
              SizedBox(height: 5),
              Text(_result),
              SizedBox(height: 10),
            ],
            ElevatedButton(
              onPressed: _walletConnected ? _disconnectWallet : _connectWallet,
              child: Text(
                _walletConnected ? 'Disconnect Wallet' : 'Connect Wallet',
              ),
            ),
            if (_walletConnected) ...[
              SizedBox(height: 5),
              Text('Wallet Address: $_walletAddress'),
            ],
            if (_walletConnectUri != null) ...[
              SizedBox(height: 20),
              Text('Scan QR code with your wallet app:'),
              SizedBox(height: 10),
              Center(
                child: QrImageView(
                  data: _walletConnectUri!,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
