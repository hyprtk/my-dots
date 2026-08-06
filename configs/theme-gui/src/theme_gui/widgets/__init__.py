from gi.repository import Gtk


def get_children(widget) -> list:
    """Get all children of a GTK4 widget (replaces deprecated get_children)."""
    children = []
    child = widget.get_first_child()
    while child is not None:
        children.append(child)
        child = child.get_next_sibling()
    return children


def remove_all_children(widget):
    """Remove all children from a GTK4 widget."""
    while True:
        child = widget.get_first_child()
        if child is None:
            break
        widget.remove(child)
