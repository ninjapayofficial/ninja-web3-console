// lib/contract_interface_page.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web3dart/web3dart.dart';
import 'package:flutter_web3/flutter_web3.dart' as fw3;

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
  String? _abiString; // Store the ABI as a String
  List<ContractFunction> _readFunctions = [];
  List<ContractFunction> _writeFunctions = [];

  DeployedContract? _deployedContract;
  ContractFunction? _selectedFunction;
  List<TextEditingController> _paramControllers = [];

  String _result = '';

  late Web3Client _client;

  @override
  void initState() {
    super.initState();
    // Replace with your Ethereum node URL (Infura)
    String rpcUrl =
        'https://sepolia.infura.io/v3/5e5afd85b4aa4e7ab3719e32e9eee3a2'; // Replace with your Infura project ID
    _client = Web3Client(rpcUrl, http.Client());
  }

  @override
  void dispose() {
    _contractAddressController.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _connectWallet() async {
    if (!fw3.Ethereum.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MetaMask is not available in your browser')),
      );
      return;
    }

    try {
      final accounts = await fw3.ethereum!.requestAccount();
      fw3.ethereum!.onAccountsChanged((accounts) {
        setState(() {
          _walletAddress = accounts.first;
        });
      });

      setState(() {
        _walletAddress = accounts.first;
        _walletConnected = true;
      });
    } on fw3.EthereumUserRejected {
      print('User rejected the connection request');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User rejected the connection request')),
      );
    } catch (e) {
      print('Error connecting wallet: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect wallet')),
      );
    }
  }

  Future<void> _disconnectWallet() async {
    // Note: MetaMask does not support programmatic disconnection
    setState(() {
      _walletAddress = '';
      _walletConnected = false;
    });
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
    String apiKey =
        'TZU9YP9Y15NI9W9TYHV6NGFZ78IVBKJ1WZ'; // Replace with your Etherscan API key
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
        _abiString = abiString; // Store the ABI string
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

    // Ensure that _abiString is not null
    if (_abiString == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('ABI is not loaded. Please load the contract first.')),
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
          parsedValue = value; // Use the address string directly
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
        final contract = fw3.Contract(
          _contractAddress,
          _abiString!, // Use the ABI string here
          fw3.provider!,
        );

        final result = await contract.call<dynamic>(
          _selectedFunction!.name,
          params,
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

        final contract = fw3.Contract(
          _contractAddress,
          _abiString!, // Use the ABI string here
          fw3.provider!.getSigner(),
        );

        // Send transaction
        // final txResponse = await contract.send(
        //   _selectedFunction!.name,
        //   params,
        // );
        final txResponse = await contract.send(
          _selectedFunction!.name,
          params,
          fw3.TransactionOverride(
            nonce: 68,
            // gasLimit: BigInt.from(300000), // Adjust as needed
            // gasPrice: BigInt.parse('50000000000'), // 50 Gwei in wei
            // Optionally, use maxPriorityFeePerGas and maxFeePerGas for EIP-1559 transactions
          ),
        );

        final txReceipt =
            await txResponse.wait(); // Wait for the transaction to be mined

        setState(() {
          _result = 'Transaction confirmed in block ${txReceipt.blockNumber}';
        });
      }
    } catch (e, stackTrace) {
      print('Error calling function: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calling function: $e')),
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
          ],
        ),
      ),
    );
  }
}
