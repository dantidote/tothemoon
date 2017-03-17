#!/usr/bin/perl

use REST::Client;
use JSON;
use MIME::Base64;
use Data::Dumper;
use Digest::SHA qw(hmac_sha384_hex);

my $amountToBuyInUsd = '3.33';

#my $host = 'https://api.sandbox.gemini.com';
#my $secretFile = '/media/storage/Backup/gemini_sandbox_api_secret';
#my $apiKeyFile = '/media/storage/Backup/gemini_sandbox_api_key';

my $host = 'https://api.gemini.com';
my $secretFile = '/media/storage/Backup/gemini_api_secret';
my $apiKeyFile = '/media/storage/Backup/gemini_api_key';

open( my $fh, '<', $secretFile ) or die "Can't open $secretFile: $!";
my $apiSecret = <$fh>;
chomp $apiSecret;
close $fh;

open( my $fh, '<', $apiKeyFile ) or die "Can't open $apiKeyFile: $!";
my $apiKey = <$fh>;
chomp $apiKey;
close $fh;

checkFunds();
buyBtc();

sub getNonce(){

 my $nonce = `date +%s%N`;
 chomp $nonce;
 return $nonce;

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
 
 #Can't guarantee the array order. Must iterate through to find the USD wallet.
 foreach $wallet (@$wallets){
  if( $wallet->{currency} eq "USD" ){
    if( $wallet->{available} > $amountToBuyInUsd ){
      return 0;
    }
    else{
      die "not enough USD";
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
