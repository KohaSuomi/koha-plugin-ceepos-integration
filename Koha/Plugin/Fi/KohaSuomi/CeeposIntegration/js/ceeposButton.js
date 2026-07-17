$(document).ready(function () {
  if (
    window.location.pathname == "/cgi-bin/koha/members/paycollect.pl" &&
    !window.location.search.includes("WRITEOFF")
  ) {
    if (
      ceeposBranches.includes(
        $("#logged-in-info-full .logged-in-branch-code").text()
      )
    ) {
      let htmlLang = document.documentElement.lang || 'en';
      htmlLang = htmlLang.split('-')[0];
      if (!['en', 'fi', 'sv'].includes(htmlLang)) {
        htmlLang = 'en';
      }
      $("#payfine .action, #payindivfine .action")
        .find("input")
        .last()
        .hide()
        .after(
          '<input type="button" id="CeeposMaksu" class="btn btn-primary" style="margin-left:3px;" value="' +
            {
              en: "Ceepos Payment",
              fi: "Ceepos-maksu",
              sv: "Ceepos-betalning"
            }[htmlLang] +
            '" onclick="setCeeposPayment($(this))"/>'
        );
      if (localStorage.getItem("ceeposOffice")) {
        $("#payment_type").val(localStorage.getItem("ceeposOffice"));
      }
    }
  }
  $("#paycollect").hide();
  $("#circmessages a[href*='/cgi-bin/koha/members/paycollect.pl'").hide();
  $("#patron_messages a[href*='/cgi-bin/koha/members/paycollect.pl'").hide();

  // Hide paycollect button on circulation.pl page
  if (window.location.pathname == "/cgi-bin/koha/circ/circulation.pl") {
    $("a[href*='/cgi-bin/koha/members/paycollect.pl']").hide();
  }
});

function setCeeposPayment(element) {
  var ceeposOffice = $("#payment_type").find(":selected").val();
  localStorage.setItem("ceeposOffice", ceeposOffice);
  let payments;
  let borrowernumber;
  if ($("#payindivfine").find("#pay_individual").val() == 'cud-pay_individual') {
    borrowernumber = $("#payindivfine").find("#borrowernumber").val();
    payments = [
      {
        borrowernumber: $("#payindivfine").find("#borrowernumber").val(),
        accountlines_id: $("#payindivfine").find("#accountlines_id").val(),
        description: $("#payindivfine").find("#description").val(),
        amountoutstanding: $("#payindivfine").find("#amountoutstanding").val(),
        payment_type: $("#payindivfine").find("#debit_type_code").val(),
        office: ceeposOffice,
      },
    ];
  } else {
    borrowernumber = $("#payfine").find("#borrowernumber").val();
    payments = [
      {
        borrowernumber: $("#payfine").find("#borrowernumber").val(),
        accountlines: $("#payfine").find("#selected_accts").val(),
        amountoutstanding: $("#payfine").find("#collected").val(),
        office: ceeposOffice,
      },
    ];
  }
  $.ajax({
    url: "/api/v1/contrib/kohasuomi/payments/ceepos",
    type: "POST",
    dataType: "json",
    contentType: "application/json; charset=utf-8",
    data: JSON.stringify(payments),
    beforeSend: function () {
      $("#CeeposMaksu").attr("disabled", true);
    },
    success: function (result) {
      alert("Maksu lähetetty, käsittele kassassa!");
      location.href =
        "/cgi-bin/koha/members/boraccount.pl?borrowernumber=" + borrowernumber;
    },
    error: function (xhr, status, error) {
      $("#CeeposMaksu").attr("disabled", false);
      alert(JSON.parse(xhr.responseText).error);
    },
  });
}
