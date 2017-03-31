#!/usr/bin/perl

use REST::Client;
use JSON;
use MIME::Base64;
use Data::Dumper;
use Config::Simple;
use Digest::SHA qw(hmac_sha384_hex);
use Sys::Syslog;

my $configFile = 'gemini.config';

my $debug = 1;

openlog("GEMINI", 'ndelay,pid', "local0");

Config::Simple->import_from($configFile, \%config);

my $amountToBuyInUsd = $config{'amountToBuyInUsd'};
my $address = $config{'address'};
my $host = $config{'host'};
my $apiSecret = $config{'apiSecret'};
my $apiKey = $config{'apiKey'};
my $maxBTC = $config{'maxBTCToKeep'};

checkFunds();
buyBtc();

sub getNonce(){

 my $nonce = `date +%s%N`;
 chomp $nonce;
 return $nonce;

}


sub withdrawBTC{

 my $amt = shift;
 my $nonce = getNonce();

 if($debug){ print "Withdrawing $amt BTC\n" }

 my $payload = qq(
 {
    "request": "/v1/withdraw/btc",
    "nonce": $nonce,
    "address": "$address",
    "amount": "$amt"
 }
 );

 if($debug){ print "$payload\n"; }
 $enc_payload = encode_base64($payload,"");

 my $client = REST::Client->new();
 $client->setHost($host);

 $client->addHeader('X-GEMINI-APIKEY', $apiKey);
 $client->addHeader('X-GEMINI-PAYLOAD', $enc_payload);
 $client->addHeader('X-GEMINI-SIGNATURE', hmac_sha384_hex($enc_payload,$apiSecret));

 $client->POST('/v1/withdraw/btc');

 my $res = $client->responseContent();

 print $res;
}

sub checkFunds(){

 my $nonce = getNonce();
 
 my $payload = qq(
 {
    "request": "/v1/balances",
    "nonce": $nonce
 }
 );

 if($debug){ print "$payload\n"; }
 $enc_payload = encode_base64($payload,"");

 my $client = REST::Client->new();
 $client->setHost($host);

 $client->addHeader('X-GEMINI-APIKEY', $apiKey);
 $client->addHeader('X-GEMINI-PAYLOAD', $enc_payload);
 $client->addHeader('X-GEMINI-SIGNATURE', hmac_sha384_hex($enc_payload,$apiSecret));

 $client->POST('/v1/balances');

 my $res = $client->responseContent();

 my $wallets = from_json( $res );
 
 #Can't guarantee the array order. Must iterate through to find the correct wallet.
 foreach $wallet (@$wallets){
  if( $wallet->{currency} eq "USD" ){
    if($debug){ print "Current USD Balance: $wallet->{available}\n"};
    if( $wallet->{available} > $amountToBuyInUsd ){
      if($debug){ print "We have enough USD to buy BTC\n" }
      return 0;
    }
    else{
      die "not enough USD";
    }
  }
  elsif( $wallet->{currency} eq "BTC" ){
    if($debug){ print "Current BTC Balance: $wallet->{available}\n"};
    if( $wallet->{available} > $maxBTC ){
      if($debug){ print "Balance is greater than threshold.\n" }
      withdrawBTC( $wallet->{available} );
    }
    else{
      if($debug){ print "Not withdrawing BTC because your balance isn't greater than $maxBTC\n" }
    }
  }

 }
}

sub getAskPrice(){

 my $client = REST::Client->new();

 $client->setHost($host);

 $client->GET('/v1/pubticker/btcusd');

 my $res = $client->responseContent();

 $resObj = from_json( $res );
 my $ask = $resObj->{ask};
 
 #sanity
 if( $ask < 500 || $ask > 2000 ){
   die "Asking Price OutOfBounds"; 
 }
 
 return $ask;

}

sub buyBtc{

 my $nonce = getNonce();
 my $price = getAskPrice();

 $amount = sprintf("%.8f", $amountToBuyInUsd / $price) ;

 my $payload = qq(
 {
    "request": "/v1/order/new",
    "nonce": $nonce,
    "symbol": "btcusd",
    "amount": "$amount",
    "price": "$price",
    "side": "buy",
    "type": "exchange limit"
 }
 );


 if($debug){ print "$payload\n"; }
 $enc_payload = encode_base64($payload,"");

 my $client = REST::Client->new();

 $client->addHeader('X-GEMINI-APIKEY', $apiKey);
 $client->addHeader('X-GEMINI-PAYLOAD', $enc_payload);
 $client->addHeader('X-GEMINI-SIGNATURE', hmac_sha384_hex($enc_payload,$apiSecret));

 $client->setHost($host);

 $client->POST('/v1/order/new');

 print $client->responseContent();

}
