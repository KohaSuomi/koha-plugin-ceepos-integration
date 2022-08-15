# Koha-Suomi plugin CeeposIntegration

This plugin integrates Ceepos cash register to Koha

# Downloading

From the release page you can download the latest \*.kpz file

# Installing

Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

    Change <enable_plugins>0<enable_plugins> to <enable_plugins>1</enable_plugins> in your koha-conf.xml file
    Confirm that the path to <pluginsdir> exists, is correct, and is writable by the web server
    Remember to allow access to plugin directory from Apache

    <Directory <pluginsdir>>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    Restart your webserver

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

# Configuring

1. Define your connection configurations to koha-conf.xml

```
<pos>
    <CPU>
        <!-- Default payment server configuration -->
        <!-- Delivered by CPU: -->
        <source></source>                           <!-- Source id -->
        <secretKey></secretKey>                     <!-- Secret key for generating SHA-256 hash -->
        <url></url>                                 <!-- Address to the cash register server -->
        <!-- SSL certificates -->
        <ssl_cert></ssl_cert>                       <!-- SSL certificate path -->
        <ssl_key></ssl_key>                         <!-- SSL key path -->
        <ssl_ca_file></ssl_ca_file>                 <!-- CA certificate path -->

        <!-- Per branch payment server configuration -->
        <branchcode>
            <!--
                Example:

                <CPL>
                    <source></source>
                    <secretKey></secretKey>
                    <url></url>
                    <ssl_cert></ssl_cert>
                    <ssl_key></ssl_key>
                    <ssl_ca_file></ssl_ca_file>
                </CPL>
                <MPL>
                    ...
                </MPL>
            -->
        </branchcode>

        <!-- Koha settings -->
        <mode></mode>                               <!-- Use 2 for synchronized mode -->
        <notificationAddress></notificationAddress> <!-- https://server/api/v1/contrib/kohasuomi/payments/ceepos/report -->
        <!-- Replace "server" with your server address -->
        <!-- Use "borrower" for borrower information. Any other value will default to transaction id -->
        <receiptDescription>id</receiptDescription>
    </CPU>
</pos>

```
2. Define offices to PAYMENT_TYPE authorized value. If ILS has more Ceepos sources then name the payment type as source+office, like KOHA10.
3. Define Koha-Ceepos product mapping yaml to plugin's settings. Add library code and into it Koha product name and Ceepos product name.
```
CPL:
 MANUAL: 1111
 NEW_CARD: 3222
```
4. Add this to intranetuserjs

```
$(document).ready(function() {
  let ceeposBranches = ['CPL']; // Define the button visibility by library
  if (ceeposBranches.includes($("#logged-in-info-full .logged-in-branch-code").text())) {
   $("#payfine .action, #payindivfine .action").find("input").after('<input type="button" id="CeeposMaksu" style="margin-left:3px;" value="Ceeposmaksu" onclick="setCeeposPayment($(this))"/>');
   if(localStorage.getItem('ceeposOffice')){
    $('#payment_type').val(localStorage.getItem('ceeposOffice'));
   }
  }
  $('#paycollect').hide();
});

function setCeeposPayment(element) {
  var ceeposOffice = $('#payment_type').find(":selected").val();
  localStorage.setItem('ceeposOffice', ceeposOffice);
  	let payments;
  	let borrowernumber;
    if($("#payindivfine").find("#pay_individual").val() == 1) {
       borrowernumber = $("#payindivfine").find("#borrowernumber").val();
       payments = [{'borrowernumber': $("#payindivfine").find("#borrowernumber").val(), 'accountlines_id': $("#payindivfine").find("#accountlines_id").val(), 'description': $("#payindivfine").find("#description").val(), 'amountoutstanding': $("#payindivfine").find("#collected").val(), 'payment_type': $("#payindivfine").find("#debit_type_code").val(), 'office': ceeposOffice}];
    } else {
        borrowernumber = $("#payfine").find("#borrowernumber").val();
        payments = [{'borrowernumber': $("#payfine").find("#borrowernumber").val(), 'accountlines': $("#payfine").find("#selected_accts").val(), 'amountoutstanding': $("#payfine").find("#collected").val(), 'office': ceeposOffice}];
    }
    $.ajax({
     url: "/api/v1/contrib/kohasuomi/payments/ceepos", 
     type: "POST",
     dataType: "json",
     contentType: "application/json; charset=utf-8",
     data: JSON.stringify(payments),
     beforeSend: function() {
        $("#CeeposMaksu").attr("disabled", true);
        alert("Maksu lähetetty, käsittele kassassa");
     },
     success: function (result) {
         location.href = '/cgi-bin/koha/members/boraccount.pl?borrowernumber='+borrowernumber;
      },
      error: function (xhr, status, error) {
          $("#CeeposMaksu").attr("disabled", false);
          alert(JSON.parse(xhr.responseText).error);
      }
   });
}
```

# Logging

Set logging for ceepos to log4perl.conf file

```
log4perl.logger.ceepos = INFO, CEEPOS
log4perl.appender.CEEPOS=Log::Log4perl::Appender::File
log4perl.appender.CEEPOS.filename=/var/log/koha/ceepos.log
log4perl.appender.CEEPOS.mode=append
log4perl.appender.CEEPOS.layout=PatternLayout
log4perl.appender.CEEPOS.layout.ConversionPattern=[%d] [%p] %m
log4perl.appender.CEEPOS.utf8=1

```
