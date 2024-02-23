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
      $("#payfine .action, #payindivfine .action")
        .find("input")
        .hide()
        .after(
          '<input type="button" id="CeeposMaksu" style="margin-left:3px;" value="Ceeposmaksu" onclick="setCeeposPayment($(this))"/>'
        );
      if (localStorage.getItem("ceeposOffice")) {
        $("#payment_type").val(localStorage.getItem("ceeposOffice"));
      }
    }
    $("#paycollect").hide();
    $("#circmessages a[href*='/cgi-bin/koha/members/paycollect.pl'").hide();
    $("#patron_messages a[href*='/cgi-bin/koha/members/paycollect.pl'").hide();
  }
});

function setCeeposPayment(element) {
  var ceeposOffice = $("#payment_type").find(":selected").val();
  localStorage.setItem("ceeposOffice", ceeposOffice);
  let payments;
  let borrowernumber;
  if ($("#payindivfine").find("#pay_individual").val() == 1) {
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
      alert("Maksu lähetetty, käsittele kassassa!");
    },
    success: function (result) {
      location.href =
        "/cgi-bin/koha/members/boraccount.pl?borrowernumber=" + borrowernumber;
    },
    error: function (xhr, status, error) {
      $("#CeeposMaksu").attr("disabled", false);
      alert(JSON.parse(xhr.responseText).error);
    },
  });
}
