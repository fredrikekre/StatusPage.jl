window.onload = function() {
    var x = document.getElementsByClassName("last-update");
    var len = x.length;
    for (var i = 0; i < len; i++) {
        var inner = x[i].innerHTML;
        if (inner == 'N/A') { break; }
        var generated = new Date(inner);
        var current = new Date();
        var diff = Math.round((current - generated)/1000/60);
        var plural = diff == 1 ? '' : 's';
        x[i].innerHTML = diff + ' minute' + plural + ' ago';
    }
};
