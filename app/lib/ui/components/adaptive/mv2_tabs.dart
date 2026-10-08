/// The shell's five destinations, in bar order.
///
/// 发布 sits in the middle of the bar but is not a branch: the shell
/// intercepts it and opens the composer instead of switching branch
/// (`selectShellTab`).
enum Mv2Tab { feed, nodes, publish, notifications, profile }
