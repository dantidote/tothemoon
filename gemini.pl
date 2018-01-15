#!/usr/bin/perl

use REST::Client;
use JSON;
use MIME::Base64;
use Data::Dumper;
use Config::Simple;
use Digest::SHA qw(hmac_sha384_hex);
use Sys::Syslog;
use Cwd 'abs_path';

my $scriptDir = abs_path($0) =~ s/[^\/]+$//r ;

my $configFile = 'gemini.config';

my $configFile = $scriptDir . $configFile;

my $debug = 1;

openlog("GEMINI", 'ndelay,pid', "local0");

Config::Simple->import_from($configFile, \%config) or die;

my $btcToBuyInUsd = $config{'btcToBuyInUsd'};
my $ethToBuyInUsd = $config{'ethToBuyInUsd'};
my $address = $config{'address'};
my $host = $config{'host'};
my $apiSecret = $config{'apiSecret'};
my $apiKey = $config{'apiKey'};
my $maxBTC = $config{'maxBTCToKeep'};
my $email = $config{'email'};
my $lowFundAmt = $config{'lowFundAmt'};


checkFunds();
buyBtc();
buyEth();

sub getNonce(){

 my $nonce = `date +%s%N`;
 chomp $nonce;
 return $nonce;

}


sub withdrawBTC{

 my $amt = shift;
 my $nonce = getNonce();

 syslog("info", "Withdrawing $amt BTC");

 my $payload = qq(
 {
    "request": "/v1/withdraw/btc",
    "nonce": $nonce,
    "address": "$address",
    "amount": "$amt"
 }
 );

 if($debug){ print $payload ;}
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

 if($debug){ print $payload ;}
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
    syslog("info", "Current USD Balance: $wallet->{available}");
     if( $wallet->{available} < $lowFundAmt ){
      system("mail -s \"Gemini Funds Low\" $email ");
    }

    if( $wallet->{available} > $btcToBuyInUsd+$ethToBuyInUsd ){
      syslog("info", "We have enough USD to buy BTC");
      return 0;
    }
    else{
      die "not enough USD";
    }
  }
  elsif( $wallet->{currency} eq "BTC" ){
    syslog("info", "Current BTC Balance: $wallet->{availableForWithdrawal}");
    if( $wallet->{availableForWithdrawal} > $maxBTC ){
      syslog("info",  "Balance is greater than threshold.");
      withdrawBTC( $wallet->{availableForWithdrawal} );
    }
    else{
      syslog("info",  "Not withdrawing BTC because your balance isn't greater than $maxBTC");
    }
  }

 }
}

sub getAskPrice{
 my $currency = shift;
 my $client = REST::Client->new();

 $client->setHost($host);
 if( $currency eq "BTC" ){ $client->GET('/v1/pubticker/btcusd') }
 elsif( $currency eq "ETH" ){ $client->GET('/v1/pubticker/ethusd') }
 else{ syslog("error", "No valid currency specified when getting ask price.") }

 my $res = $client->responseContent();

 $resObj = from_json( $res );
 my $ask = $resObj->{ask};
 
 #sanity
# if( $ask < 500 || $ask > 20000 ){
#   syslog("info",  "Price out of bounds: $ask ");
#   die "Asking Price OutOfBounds"; 
# }
 
 return $ask;

}

sub buyBtc{

 my $nonce = getNonce();
 my $price = getAskPrice("BTC");

 my $amount = sprintf("%.8f", $btcToBuyInUsd / $price) ;

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


 if($debug){ print $payload ;}
 $enc_payload = encode_base64($payload,"");

 my $client = REST::Client->new();

 $client->addHeader('X-GEMINI-APIKEY', $apiKey);
 $client->addHeader('X-GEMINI-PAYLOAD', $enc_payload);
 $client->addHeader('X-GEMINI-SIGNATURE', hmac_sha384_hex($enc_payload,$apiSecret));

 $client->setHost($host);

 $client->POST('/v1/order/new');
 if( $client->responseCode == 200 ){
   syslog("info", "Purchase Complete");
 }
 else{
   syslog("error", "Purchase Failed");
   print $client->responseContent();
 }
}



sub buyEth{

 my $nonce = getNonce();
 my $price = getAskPrice('ETH');

 my $amount = sprintf("%.6f", $ethToBuyInUsd / $price) ;

 my $payload = qq(
 {
    "request": "/v1/order/new",
    "nonce": $nonce,
    "symbol": "ethusd",
    "amount": "$amount",
    "price": "$price",
    "side": "buy",
    "type": "exchange limit"
 }
 );


 if($debug){ print $payload ;}
 $enc_payload = encode_base64($payload,"");

 my $client = REST::Client->new();

 $client->addHeader('X-GEMINI-APIKEY', $apiKey);
 $client->addHeader('X-GEMINI-PAYLOAD', $enc_payload);
 $client->addHeader('X-GEMINI-SIGNATURE', hmac_sha384_hex($enc_payload,$apiSecret));

 $client->setHost($host);

 $client->POST('/v1/order/new');
 if( $client->responseCode == 200 ){
   syslog("info", "Purchase Complete");
 }
 else{
   syslog("err", "Purchase Failed");
   print $client->responseContent();
 }
}
